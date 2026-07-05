# Migrating from WinBUGS, OpenBUGS, and JAGS

If you have models written for [`WinBUGS`](https://www.mrc-bsu.cam.ac.uk/software/), [`OpenBUGS`](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html), [`MultiBUGS`](https://www.multibugs.org/documentation/latest/), [`JAGS`](https://mcmc-jags.sourceforge.io/), or [`nimble`](https://r-nimble.org/), most of them will run in JuliaBUGS with few or no changes: the `@bugs` macro accepts the original BUGS syntax verbatim. What changes is the workflow around the model — how you supply data and initial values, how you run the sampler, and how you read the results. This page maps the old workflow onto the new one, walks through a complete migration of a classic example, and lists the places where the JuliaBUGS language differs from the classic implementations.

One difference worth knowing up front: WinBUGS, OpenBUGS, and JAGS choose their samplers automatically (typically Gibbs-style updates). In JuliaBUGS you name the sampler yourself, and the usual choice is NUTS, a gradient-based sampler that often mixes better on the same models. Because of this, results will match the published BUGS examples in distribution, but not draw for draw.

## Your workflow, translated

| WinBUGS / OpenBUGS / JAGS | JuliaBUGS |
|:---|:---|
| Model in a text file, `model { ... }` | The `@bugs` macro. The string form runs your original program text verbatim; there is also an optional Julia-native form (a light rewrite). |
| Data as an R `list()` or rectangular text | A Julia `NamedTuple`, e.g. `(N = 21, r = [10, 23, ...])` |
| Initial values as an R `list()`, one per chain | `initialize!(model, inits)` after compiling, or the `init_params` keyword when sampling |
| Compile the model, then `update()` for burn-in and sampling (in JAGS: `jags.model()` then `update()`) | `model = seeds(data)` to compile, then a single call to `AbstractMCMC.sample(model, NUTS(0.8), 2000; ...)` — adaptation and burn-in are handled by its `n_adapts` and `discard_initial` keywords |
| CODA files / `coda.samples()` for summaries | `sample` returns a chain object directly (a FlexiChains or MCMCChains chain); `summarystats(chain)` prints the familiar table of means, standard deviations, and diagnostics |

The full workflow, end to end, is shown in [Getting Started](../getting_started.md). The rest of this page focuses on the migration itself.

## A worked migration

Let us migrate the *Seeds* example from Volume 1 of the classic BUGS examples — a random-effects logistic regression for the proportion of seeds that germinated on each of 21 plates.

### Step 1: run the original program verbatim

Paste the original program, untouched, into the string form of `@bugs`:

```julia
using JuliaBUGS

seeds = @bugs("""
model {
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma <- 1 / sqrt(tau)
}
""")
```

Everything works as it did before: `<-` for deterministic assignment, `~` for stochastic relations, the `logit(p[i]) <- ...` link-function syntax, and the `model { ... }` wrapper.

The string form takes two optional arguments after the program text, `@bugs(program, replace_period, no_enclosure)`:

  - **`replace_period`** (default `true`): BUGS allows periods inside names, like `alpha.c`, but Julia does not, so periods are replaced with underscores — `alpha.c` becomes `alpha_c`. Keep this in mind when you prepare data and initial values and when you read the results: use `alpha_c`, not `alpha.c`. Pass `false` to disable the replacement (only useful if your program has no dotted names).
  - **`no_enclosure`** (default `false`): pass `true` if your program text is just the body of the model, *without* the `model { ... }` wrapper — some people keep only the statements in their model file. If the wrapper is present, leave this at its default.

So, for example, `@bugs(program_text, true, true)` parses a wrapper-less program with dotted names translated to underscores.

### Step 2 (optional): rewrite in Julia-native syntax

You do not have to do this — the string form above is fully supported. But if you plan to keep developing the model, the Julia-native form gives you syntax highlighting, precise error locations, and generally easier debugging in Julia editors and notebooks. The same Seeds model reads:

```julia
seeds = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

The changes are mechanical:

  - The `model { ... }` wrapper and curly braces become a `begin ... end` block, and `for` loops lose their parentheses and end with `end`.
  - Deterministic assignment `<-` becomes `=` (stochastic `~` is unchanged).
  - The link function moves from the left-hand side to the right-hand side as its inverse: `logit(p[i]) <- ...` becomes `p[i] = logistic(...)`. This is necessary because Julia reads `f(x) = ...` as a function definition. See [Link functions](#Link-functions) below for the full mapping.

Both forms produce exactly the same model.

### Step 3: translate the data and initial values

In WinBUGS or JAGS the Seeds data would be an R list:

```R
list(r = c(10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3),
     n = c(39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7),
     x1 = c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
     x2 = c(0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1),
     N = 21)
```

In JuliaBUGS it becomes a `NamedTuple` — the translation is `list(...)` to `(...)`, `=` stays, and `c(...)` becomes a square-bracketed array `[...]`:

```julia
data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)
```

The names must match the variables in the model (after the period-to-underscore translation, if your names had dots).

!!! warning "Matrices: mind the filling order"
    WinBUGS and OpenBUGS data files write matrices as `structure(.Data = c(...), .Dim = c(nrow, ncol))`, and the values are listed **row by row**. Julia, like R, fills arrays **column by column**, so a plain `reshape(values, nrow, ncol)` would scramble a WinBUGS-style matrix. Translate it as `permutedims(reshape(values, ncol, nrow))` — reshape into the transposed shape, then flip. If your data instead comes from an R dump file (the JAGS convention), the values are already in column order and `reshape(values, nrow, ncol)` is correct as-is.

Initial values translate the same way as data — an R `list()` becomes a `NamedTuple` — and are supplied after compiling the model:

```julia
inits = (alpha0 = 0, alpha1 = 0, alpha2 = 0, alpha12 = 0, tau = 10)

model = seeds(data)
initialize!(model, inits)
```

Any parameter you leave out of `inits` is initialized by drawing from its prior, which matches the "gen inits" behavior of the classic programs. You can also pass initial values directly to `AbstractMCMC.sample` through its `init_params` keyword. From here, sampling and summarizing work exactly as in [Getting Started](../getting_started.md).

!!! tip "The Volume 1 examples ship with JuliaBUGS"
    All examples from Volume 1 of the classic BUGS examples come pre-translated in `JuliaBUGS.BUGSExamples.VOLUME_1`. Each entry — for instance `JuliaBUGS.BUGSExamples.VOLUME_1.seeds` — carries the translated model as `.model_def`, plus `.data`, `.inits`, and the published `.reference_results`. They are handy for cross-checking your own translations.

## Language differences

Beyond the workflow, there are a few places where the JuliaBUGS language accepts more, or asks for something slightly different, than the classic implementations. This comparison is not exhaustive, and we welcome any further discussion and reports on the matter.

### Link functions

BUGS supports four link functions: `log`, `logit`, `cloglog`, and `probit`. These functions are used to support Generalized Linear Models and, in some cases, to transform random variables with constrained support to the real line. The Seeds example migrated above uses one: `logit(p[i]) <- ...`.

JuliaBUGS inherits these functions, and the link-function syntax is fully supported when the program is written in the original BUGS syntax (the string form of `@bugs`). It is *not* supported in the Julia-native syntax, because Julia uses `f(...) = ...` to define functions, and the link-function syntax would be confusing in the Julia context.

Instead, when writing Julia-native syntax, call the *inverse* of the link function on the right-hand side of the statement. The inverse functions are:

  - `log` → `exp`
  - `logit` → `logistic`
  - `cloglog` → `cloglog`
  - `probit` → `probit`

So a statement like

```S
logit(p[i]) <- alpha0 + alpha1 * x1[i]
```

is rewritten as

```julia
p[i] = logistic(alpha0 + alpha1 * x1[i])
```

exactly as in the worked migration above.

It's also worth noting that JuliaBUGS uses [`Bijectors.jl`](https://turinglang.org/Bijectors.jl/dev/) to handle constrained parameters.

#### Compare with `nimble`

In the BUGS language, link functions are only supported in logical assignments. However, `nimble` extends this functionality by allowing link functions to be used in stochastic assignments as well; `nimble` creates new nodes as intermediate variables. JuliaBUGS doesn't currently support this syntax.

### Use of generic expressions in distribution arguments

In `WinBUGS`, `OpenBUGS`, and `MultiBUGS`, the arguments to distribution functions are typically restricted to variables or constants, not general expressions. JuliaBUGS, however, allows for more flexibility in these arguments.

For example, the following expressions are allowed in all BUGS implementations, including JuliaBUGS (assuming `y = [1, 2, 3]`):

```S
model {
 x ~ dnorm(y[y[2]], 1)
}

model {
  x ~ dnorm(y[y[2]+1], 1)
}
```

However, JuliaBUGS allows more flexibility in these arguments. The following expressions, which are not allowed in traditional BUGS implementations, are permitted in JuliaBUGS:

```S
model {
 x ~ dnorm(y[1] + 1, 1)
}

model {
 x ~ dnorm(sum(y[1:2]), 1)
}

model {
 x ~ dnorm(y[sum(y[1:2])], 1)
}
```

This means that helper quantities you would previously have assigned to an intermediate node purely to satisfy the syntax can often be written inline.

### `cumulative`, `density`, and `deviance` functions

In [`OpenBUGS`](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html), there are several functions for working with distributions:

  - `cumulative(s1, s2)`: Computes the tail area (cumulative distribution function) of the distribution of s1 up to the value of s2. s1 must be a stochastic node, and s1 and s2 can be the same.
  - `density(s1, s2)`: Computes the density function of the distribution of s1 at the value of s2. s1 must be a stochastic node supplied as data, and s1 and s2 can be the same.
  - `deviance(s1, s2)`: Computes the deviance of the distribution of s1 at the value of s2. s1 must be a stochastic node supplied as data, and s1 and s2 can be the same.

In [`MultiBUGS`](https://www.multibugs.org/documentation/latest/Functions.html), these functions have been replaced with the `cdf.dist`, `pdf.dist`, and `dev.dist` family of functions.

In JuliaBUGS, we don't have these functions directly, but similar functionality can be achieved using the `Distributions.jl` package:

  - The [`cdf`](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.cdf-Tuple{UnivariateDistribution,%20Real}) function computes the cumulative distribution function of a given univariate distribution at a specified value.
  - The [`pdf`](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.pdf-Tuple{UnivariateDistribution,%20Real}) function computes the probability density function of a given univariate distribution at a specified value.
  - JuliaBUGS does not currently support a `deviance` function equivalent to the one in OpenBUGS.

The `cdf` and `pdf` functions from `Distributions.jl` are simple to use: the first argument is the distribution, and the second argument is the value at which to evaluate the function.

An OpenBUGS program like

```S
model {
    x ~ dnorm(0, 1)
    cumulative.x = cumulative(x, x)
}
```

will need to be rewritten to:

```julia
@bugs begin
    x ~ Normal(0, 1)
    cumulative_x = cdf(Normal(0, 1), x)
end
```

### Use `:` for slicing when using Julia syntax

In the original BUGS language, slicing is performed using syntax like `x[, ]`, which selects all elements from both the first and second dimensions.

The `@bugs` macro will automatically insert a `:` when given `x[]`; however, the Julia parser will throw an error if it encounters `x[, ]`, so when using the Julia-native syntax, you must explicitly use the colon (`:`) operator for slicing. For example, to select all elements from both dimensions of an array `x`, write `x[:, :]`.

## Further reading

  - [Getting Started](../getting_started.md) — the complete workflow from model definition to summary statistics.
  - [Example Gallery](../examples/index.md) — the classic Volume 1 examples, translated and runnable.
  - [Understanding Pitfalls in Model Definitions](pitfalls.md) — behaviors that surprise people coming from other BUGS systems.
  - [BUGS Implementation Tricks](tricks.md) — classic BUGS tricks (like the zeros trick) and their JuliaBUGS equivalents.
