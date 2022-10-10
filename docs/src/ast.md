## Syntax & model representation

We provide some convenience functions to work with graphical models syntactically in Julia, inspired very much by [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/).
BUGS (Bayesian inference Using Gibbs Sampling), as the name says, is a probabilistic programming system originally designed for Gibbs sampling.
For this purpose, BUGS models define, implicitly, only a directed graph of variables, not an ordered sequence of statements like other PPLs.
They do have the advantage of being relatively restricted (while still able to express a very large class of practically used models), and hence allowing lots of static analysis.  
Specifically, stochastic control flow is disallowed (except for the “mixture model” case of indexing by a stochastic variable, **indexing with stochastic variable is not supported yet**).

We provide a macro solution which allows to directly use Julia code corresponding to BUGS code:

```julia
@bugsast begin
    for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - x̄)
    end
    τ ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1e-6)
    β = dnorm(0.0, 1e-6)
end
```

BUGS syntax carries over almost one-to-one to Julia.
The macro checks that only allowed syntactic forms are used and then applies some minor normalizations. The most prominent normalization is the conversion of stochastic statements (tildes) from `:call` expressions to first-class forms:

```julia
quote
    for i = 1:N
        $(Expr(:~, :(Y[i]), :(dnorm(μ[i], τ))))
        μ[i] = α + β * (x[i] - x̄)
    end
    $(Expr(:~, :τ, :(dgamma(0.001, 0.001))))
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1.0e-6)
    β = dnorm(0.0, 1.0e-6)
end
```

## Add New Functions -- this should be replaced by the `@bugsfunction` macro
It should be reasonably easy to define anything else on top of this representation by using simple `if` statements, and `Meta.isexpr`.
Interpolation (`$(…)`) is allowed in `@bugsast`; the result of the macro is a `:quote` expression, in which the interpolations are just left as is. I.e.,

```julia
@bugsast begin
    x = $(myfunc(somevalue))
end
```

will end up as 

```julia
quote
    x = $(myfunc(somevalue))
end
```

with quasi-quotation working as usual.
(Using interpolation, it is possible to construct ASTs which bypass validation and do not correspond to valid BUGS programs – use it with care.)

In addition, there is a string macro `bugsmodel` which should work with original (R-like) BUGS syntax:

```julia
bugsmodel"""
    for (i in 1:5) {
        y[i] ~ dnorm(mu[i], tau)
        mu[i] <- alpha + beta*(x[i] - mean(x[]))
    }
    
    alpha ~ dflat()
    beta ~ dflat()
    tau <- 1/sigma2
    log(sigma2) <- 2*log.sigma
    log.sigma ~ dflat()
"""
```

Internally, the only thing this does is apply a couple of regex-based substitutions to convert the code to the equivalent Julia, `Meta.parse` the result, and apply the same logic as `@bugsast`.
We encourage users to write new program using the Julia-native syntax, because of better debuggability and perks like syntax highlighting. 
But in the case of testing out legacy program, the macro upfront should work for copy-paste situations.
All variable names are preventively wrapped in var-strings; this allows R-style names like `b.abd`.

### AST structure

Basically, all forms which obviously translate from BUGS to Julia are preserved in the equivalent Julia `Expr`s (`:call`, `:for`, `:if`, `:=`, `:ref`).
The resulting code should be as close to executable as possible.
Special forms are converted, though, in order to simplify pattern matching:

- `~` statements are parsed as `:call` by Julia, and get their own form (`dc[i] ~ dunif(0, 20)` → `(:~, (:ref, :dc, :i), (:call, :dunif, 0, 20))`).
- In logical assignments with link functions, the block on the right hand side, automatically created by the Julia parser, is removed.
  The result is therefore an `:=` expression with a direct `:call` on the LHS.
- Censoring and truncation annoations are converted to `:censored` and `:truncated` forms (`dnorm(x, μ) C (, 10)` → `(:censored, (:call, :dnorm, :x, :μ), :nothing, 100)`).
  The left-out limits (`C (, 100)`) are filled with `nothing`.
  In `@bugsast`, you may just use normal calls `truncated(dist, l, r)` and `censored(dist, l, r)`, which will be raised to special forms automatically.
- Empty ranges are automatically filled with slices (`x[,]` → `(:ref, :x, :(:), :(:))`).

In addition, forms that have both a `:call` representation and their own lowered form are tried to be normalized to the latter; currently, this concerns `getindex` to `:ref`, and `:` to `:(:)`.  `LineNumberNode`s are stripped completely.


## Semantics

The semantics of BUGS are not really made explicit.  I have tried to "reconstruct" a formalization and type system, but this is still ongoing work.

BUGS programs, in contrast to some other PPLs, have the sole purpose of implicitly describing a directed graphical model.
This means that they don’t really have operational semantics – there are not declarations of variables, input, outputs, etc., nor is order relevant.
A program like

```
model
{
  for( i in 1 : N ) {
    for( j in 1 : T ) {
      Y[i , j] ~ dnorm(mu[i , j], tau.c)
      mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
    }
    alpha[i] ~ dnorm(alpha.c, alpha.tau)
    beta[i] ~ dnorm(beta.c, beta.tau)
  }
  tau.c ~ dgamma(0.001, 0.001)
  sigma <- 1 / sqrt(tau.c)
  alpha.c ~ dnorm(0.0, 1.0E-6)
  alpha.tau ~ dgamma(0.001, 0.001)
  beta.c ~ dnorm(0.0, 1.0E-6)
  beta.tau ~ dgamma(0.001, 0.001)
  alpha0 <- alpha.c - xbar * beta.c
}
```

denotes only a certain relationship between (logical or stochastic) nodes in a graph.
Variables are either names of nodes within the program (when on the LHS of a sampling or assignement statement, like `alpha` or `sigma`), or otherwise constant parts of the “data” (like `N` and `xbar`), with which a model must be combined to instantiate it.

Loops are just a form of “plate notation”: they allow to concisely express repetition of equal statements over many constant indices, and are thus equivalent to their rolled-out form given the data.

> In the BUGS language the type information is fine grained: each component of a tensor can have
> different type information. […] One common case is where some components of a tensor have
> been observed while other components need to be estimated.

In addition to standard type checking of semantic consistency between variables and function calls, like any other expression-based language does, BUGS has the additional task of making sense of the indexed variables, which can occur in many places and arbitrary order, and ensuring that stochasticity is only used where it is allowed (e.g., not on the LHS of assignments, or within loop ranges).

A “type checker” for BUGS would therefore have multiple purposes:

1. Checking semantic constraints, such as correct argument types for functions and distributions,
2. Checking stochasticity constraints, such as constantness of loop ranges,
3. Unify types, ranks, and stochasticity of all variables – which can be specified in any order.
