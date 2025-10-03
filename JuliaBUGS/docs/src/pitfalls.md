# Understanding Pitfalls in Model Definitions

## Consequence of Observations on Model Parameters

When providing observations for the parameters of a model, the dependencies may become disrupted. Consider the following example written in Julia:

```julia
model_def = @bugs begin
    a ~ Normal(0, 1)
    b ~ Normal(0, 1)
    c ~ Normal(a, b)
end

data = (a=1.0, b=2.0)
```

In this scenario, the generated graph will lack the edges `a -> c` and `b -> c`, leading the node function of `c` to become `c ~ Normal(1.0, 2.0)`.

## Ambiguity Between Constants and Observations

A subtle and possibly contentious feature of `BUGS` syntax is that the observation value of a stochastic variable is treated identically to any model parameters supplied in the `data`. The following example is legal in BUGS if `N` is provided as data:

```S
model {
    N ~ dcat(p[])
    for (i in 1:N) {
        y[i] ~ dnorm(mu, tau)
    }
    p[1] <- 0.5
    p[2] <- 0.5
}
```
