
# Rats: a normal hierarchical model {#Rats:-a-normal-hierarchical-model}

This example is taken from section 6 of Gelfand et al. (1990), and concerns 30 young rats whose weights were measured weekly for five weeks.

## Graphical Model {#Graphical-Model}
<doodle-bugs width="100%" height="600px" model="rats"></doodle-bugs>


## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end
```


== JuliaBUGS @model

```julia
@model function rats(
    (; alpha, beta, var"tau.c", var"alpha.c", var"alpha.tau", var"beta.c", var"beta.tau"),
    N, T, x, xbar, Y,
)
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end
```


== BUGS

```julia
model{
    for(i in 1:N) {
        for(j in 1:T) {
            Y[i, j] ~ dnorm(mu[i, j], tau.c)
            mu[i, j] <- alpha[i] + beta[i] * (x[j] - xbar)
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


:::
<details>
<summary><strong>Reference values for comparison</strong></summary>


| Parameter |  mean |    std |
| ---------:| -----:| ------:|
|  `alpha0` | 106.6 |   3.66 |
|  `beta.c` | 6.186 | 0.1086 |
|   `sigma` | 6.093 | 0.4643 |


_Reference posterior summaries from the BUGS Volume 1 documentation._
</details>


## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.rats
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```


## References {#References}
- [[1](/bibliography#gelfand1990)]
  
