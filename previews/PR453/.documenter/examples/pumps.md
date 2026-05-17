
# Pumps: conjugate gamma-Poisson hierarchical model {#Pumps:-conjugate-gamma-Poisson-hierarchical-model}

This example concerns the number of failures of pumps in a nuclear power plant, and uses a conjugate gamma-Poisson hierarchical model.

## Graphical Model {#Graphical-Model}
<doodle-bugs width="100%" height="600px" model="pumps"></doodle-bugs>


## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:N
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] = theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    end
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
end
```


== JuliaBUGS @model

```julia
@model function pumps((; x, theta, alpha, beta), N, t)
    for i in 1:N
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] = theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    end
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
end
```


== BUGS

```julia
model{
    for (i in 1 : N) {
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] <- theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    }
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
}
```


:::

## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.pumps
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```


## References {#References}
- [[2](/bibliography#george1993)]
  
