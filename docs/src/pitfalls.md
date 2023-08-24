# Understanding Pitfalls in Model Definitions

## Consequence of Observations on Model Parameters

When providing observations for the parameters of a model, the dependencies may become disrupted. Consider the following example written in Julia:

```julia
model_def = @bugast begin
    a ~ Normal(0, 1)
    b ~ Normal(0, 1)
    c ~ Normal(a, b)
end

data = (a=1.0, b=2.0)
```

In this scenario, the generated graph will lack the edges `a -> c` and `b -> c`, leading the node function of `c` to become `c ~ Normal(1.0, 2.0)`.

## Ambiguity Between Data and Observed Stochastic Variables

A subtle and possibly contentious feature of `BUGS` syntax is that the observation value of a stochastic variable is treated identically to any model parameters supplied in the `data`. Here's a legal example in BUGS:

```
model {
    N ~ dcat(p[])
    for (i in 1:N) {
        y[i] ~ dnorm(mu, tau)
    }
    p[1] <- 0.5
    p[2] <- 0.5
}
```

For a variable to be used as an observation in loop bounds or indexing, it must be part of the provided `data`, not a transformed variable.

This behavior is maintained in the current version of `JuliaBUGS`, although it was prohibited in the earlier `SymbolicPPL`.

### Possible Check Implementation in `JuliaBUGS`

Implementing a check for this behavior in `JuliaBUGS` is feasible. A simplistic approach could be to invalidate (e.g., mark as `missing`) all observations after the first pass and verify if any are used in loop bounds or indexing. However, there is currently no plan to implement this check.
