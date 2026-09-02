
# Seeds: random-effect logistic regression {#Seeds:-random-effect-logistic-regression}

Crowder&#39;s (1978) seed germination data: proportions of seeds of two species that germinate on two root extracts. The model is a random-effect logistic regression that accounts for overdispersion across plates.

## Graphical Model {#Graphical-Model}
<doodle-bugs width="100%" height="600px" model="seeds"></doodle-bugs>


## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
                        alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```


== JuliaBUGS @model

```julia
@model function seeds(
    (; alpha0, alpha1, alpha2, alpha12, tau, b),
    N, n, x1, x2, r,
)
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
                        alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```


== BUGS

```julia
model {
    for (i in 1 : N) {
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
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


:::
<details>
<summary><strong>Reference values for comparison</strong></summary>


| Parameter |    mean |    std |
| ---------:| -------:| ------:|
|   `sigma` |  0.2922 | 0.1467 |
|  `alpha2` |   1.356 | 0.2772 |
|  `alpha1` | 0.08902 | 0.3124 |
|  `alpha0` | -0.5499 | 0.1965 |
| `alpha12` |  -0.841 | 0.4372 |


_Reference posterior summaries from the BUGS Volume 1 documentation._
</details>


## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.seeds
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)
```


## References {#References}
- [[3](/bibliography#crowder1978)]
  
