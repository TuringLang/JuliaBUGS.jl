# BugsParser.jl

**Despite the name, this package does not (yet) actually contain a parser.**

This package contains some infrastructure to work with [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/)-style models.
BUGS models define, implicitely, only a directed graph of variables, not an ordered sequence of statements like other PPLs.
They do have the advantage of being relatively restricted (while still able to express a very large class of practically used models), and hence allowing lots of static analysis.  Specifically, stochastic control flow is disallowed (except for the “mixture model” case of indexing by a stochastic variable).

The package provides some convenience functions to work with such models syntactically in Julia, and an attempt of a type checker (which involves the inference of the trace type and analysis of variables).


## Syntactic part

The original idea was to implement an actual parser from strings to Julia ASTs (`Expr`); this turned out to be very difficult, as I have not found any reliable parsing libraries in pure Julia (stable, flexible, debuggable, and with good error reporting).
Instead, for now, there is only a macro solution:

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

This is still pretty neat, as BUGS syntax carries over almost one-to-one to Julia.
The macro’s sole purpose is to check that only allowed syntactic forms are used, and apply some minor normalizations – most prominently, the conversion of stochastic statements (tildes) from `:call` expressions to first-class forms:

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

It should be reasonably easy to define anything else on top of this representation by using simple `if` statements, and `Meta.isexpr`.


## Semantic part


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

A “type checker” for BUGS has therefore multiple purposes:

1. Checking semantic constraints, such as correct argument types for functions and distributions,
2. Checking stochasticity constraints, such as constantness of loop ranges,
3. Unify types, ranks, and stochasticity of all variables – which can be specified in any order.
