# Example: Logistic Regression with Random Effects

!!! tip "New to JuliaBUGS?"
    Start with the shorter [Getting Started](getting_started.md) tutorial; this page is the in-depth version of the same workflow.

```@setup abc
using JuliaBUGS
using AdvancedHMC, AbstractMCMC, LogDensityProblems, FlexiChains
using ADTypes, Mooncake

data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)

seeds = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end

initializations = (alpha = 1, beta = 1)
```

We will use the [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) for demonstration.
This example concerns the proportion of seeds that germinated on each of 21 plates. Here, we transform the data into a `NamedTuple`:

```julia
data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)
```

where `r[i]` is the number of germinated seeds and `n[i]` is the total number of the seeds on the $i$-th plate.
Let $p_i$ be the probability of germination on the $i$-th plate. Then, the model is defined by:

```math
\begin{aligned}
b_i &\sim \text{Normal}(0, \tau) \\
\text{logit}(p_i) &= \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
r_i &\sim \text{Binomial}(p_i, n_i)
\end{aligned}
```

where $x_{1i}$ and $x_{2i}$ are the seed type and root extract of the $i$-th plate.  
The original BUGS program for the model is:

```S
model
{
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tau)
}
```

## Modeling Language

### Writing a Model in BUGS

Language References:

- [MultiBUGS](https://www.multibugs.org/documentation/latest/)
- [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)

Implementations in C++ and R:

- [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and its [user manual](https://people.stat.sc.edu/hansont/stat740/jags_user_manual.pdf)
- [Nimble](https://r-nimble.org/)

Language Syntax:

- [BNF](https://github.com/TuringLang/JuliaBUGS.jl/blob/main/archive/parser_attempts/BNF.txt)

### Writing a Model in Julia

We provide a [macro](https://docs.julialang.org/en/v1/manual/metaprogramming/#man-macros) which allows users to write down model definitions using Julia:

```julia
seeds = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

BUGS syntax carries over almost one-to-one to Julia, with minor exceptions.
Modifications required are minor: curly braces are replaced with `begin ... end` blocks, and `for` loops do not require parentheses.
In addition, Julia uses `f(x) = ...` as a shorthand for function definition, so BUGS' link function syntax is disallowed.
Instead, user can call the inverse function of the link functions on the RHS expressions.

### Support for Legacy BUGS Programs

The `@bugs` macro also works with original (R-like) BUGS syntax:

```julia
seeds = @bugs("""
model{
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
""", true, true)
```

By default, `@bugs` will translate R-style variable names like `a.b.c` to `a_b_c`, user can pass `false` as the second argument to disable this.
User can also pass `true` as the third argument if `model { }` enclosure is not present in the BUGS program.
We still encourage users to write new programs using the Julia-native syntax, because of better debuggability and perks like syntax highlighting.

## Basic Workflow

### Compilation

The model definition returned by `@bugs` is *callable*: call it with the data (a `NamedTuple`) to construct a `BUGSModel`, which implements the [LogDensityProblems.jl](https://github.com/tpapp/LogDensityProblems.jl) interface.

```@example abc
model = seeds(data)
show(model) # hide
```

Parameter values will be sampled from the prior distributions in the original space.

!!! note "`compile` is now mostly internal"
    Calling the model definition is the supported way to construct a `BUGSModel`. It wraps `compile`, which is kept for backward compatibility (`compile(seeds, data)` does the same thing) but is now mostly an internal function — you shouldn't need to call it directly.

We can provide initial parameter values after construction with `initialize!`:

```@example abc
initializations = (alpha = 1, beta = 1)
initialize!(model, initializations)
```

`initialize!` also accepts a flat vector. In this case, the vector should have the same length as the number of parameters, but values can be in transformed space:

```@example abc
initialize!(model, rand(26))
```

### Inference

For gradient-based inference, construct your model with an AD backend using the `adtype` keyword (see [Automatic Differentiation](inference/ad.md) for details). We use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl):

```@example abc
# Construct with gradient support
model = seeds(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model); initial_θ = rand(D)

samples_and_stats = AbstractMCMC.sample(
                        model,
                        NUTS(0.8),
                        n_samples;
                        chain_type = VNChain,
                        n_adapts = n_adapts,
                        init_params = initial_θ,
                        discard_initial = n_adapts,
                        progress = false
                    )
summarystats(samples_and_stats)
```

This is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

Here `chain_type = VNChain` collects the samples into a [`FlexiChains.FlexiChain`](https://github.com/penelopeysm/FlexiChains.jl) keyed by variable name. `MCMCChains` is also still supported: load it and pass `chain_type = MCMCChains.Chains` instead (or convert an existing chain with `MCMCChains.Chains(samples_and_stats)`).

## Next Steps

- [Automatic Differentiation](inference/ad.md) - AD backends and configuration
- [Evaluation Modes](inference/evaluation_modes.md) - Different log density computation modes
- [Auto-Marginalization](inference/auto_marginalization.md) - Gradient-based inference with discrete variables
- [Parallel Sampling](inference/parallel.md) - Multi-threaded and distributed sampling

## More Examples

We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/main/JuliaBUGS/src/BUGSExamples/Volume_1)). All programs and data are included, and can be compiled using the steps described in the tutorial above.

More worked Julia scripts are available in the [examples directory](https://github.com/TuringLang/JuliaBUGS.jl/tree/main/JuliaBUGS/examples), including SIR, Gaussian process, and Bayesian neural network examples using Mooncake-backed gradient sampling.
