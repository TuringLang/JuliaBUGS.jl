# BugsModels.jl

SymbolicPPL.jl implements is a [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/)-style DSL. A program 
BUGS (Bayesian inference Using Gibbs Sampling), as the name says, is a probabilistic programming system originally designed for Gibbs sampling.
For this purpose, BUGS models define, implicitely, only a directed graph of variables, not an ordered sequence of statements like other PPLs.
They do have the advantage of being relatively restricted (while still able to express a very large class of practically used models), and hence allowing lots of static analysis.  Specifically, stochastic control flow is disallowed (except for the “mixture model” case of indexing by a stochastic variable).

## Program Syntax
Julia code corresponding to BUGS code:

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

This is pretty neat, as BUGS syntax carries over almost one-to-one to Julia.


## Support of Legacy BUGS Program
Use the `bugsmodel` string macro.