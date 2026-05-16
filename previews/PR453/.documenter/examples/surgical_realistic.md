
# Surgical (realistic): random-effects logistic regression for hospital rates {#Surgical-realistic:-random-effects-logistic-regression-for-hospital-rates}

Mortality rates following cardiac surgery in 12 hospitals, modelled with a random-effects logistic regression that pools information across hospitals. This is the &quot;realistic&quot; model in BUGS Volume 1; the simple counterpart fits independent Beta(1, 1) priors per hospital.

## Graphical Model {#Graphical-Model}
<doodle-bugs width="100%" height="600px" model="surgical"></doodle-bugs>


## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:N
        b[i] ~ dnorm(mu, tau)
        r[i] ~ dbin(p[i], n[i])
        p[i] = logistic(b[i])
    end
    var"pop.mean" = exp(mu) / (1 + exp(mu))
    mu  ~ dnorm(0.0, 1.0e-6)
    sigma = 1 / sqrt(tau)
    tau ~ dgamma(0.001, 0.001)
end
```


== JuliaBUGS @model

```julia
@model function surgical_realistic((; b, mu, tau), N, n, r)
    for i in 1:N
        b[i] ~ dnorm(mu, tau)
        r[i] ~ dbin(p[i], n[i])
        p[i] = logistic(b[i])
    end
    var"pop.mean" = exp(mu) / (1 + exp(mu))
    mu  ~ dnorm(0.0, 1.0e-6)
    sigma = 1 / sqrt(tau)
    tau ~ dgamma(0.001, 0.001)
end
```


== BUGS

```julia
model {
    for (i in 1 : N) {
        b[i] ~ dnorm(mu, tau)
        r[i] ~ dbin(p[i], n[i])
        p[i] <- logistic(b[i])
    }
    pop.mean <- exp(mu) / (1 + exp(mu))
    mu  ~ dnorm(0.0, 1.0E-6)
    sigma <- 1 / sqrt(tau)
    tau ~ dgamma(0.001, 0.001)
}
```


:::

## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.surgical_realistic
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```

