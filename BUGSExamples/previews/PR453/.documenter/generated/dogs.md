
# Dogs: loglinear model for binary data {#Dogs:-loglinear-model-for-binary-data}

A reanalysis of Solomon-Wynne avoidance-learning data: 30 dogs each receive 25 trials in a shuttle-box, where avoiding a shock after a warning stimulus is the success event. The model fits a loglinear specification for the probability of failure as a function of cumulative avoidances and shocks.

## Model {#Model}

::: tabs

== JuliaBUGS @bugs

```julia
@bugs begin
    for i in 1:Dogs
        xa[i, 1] = 0
        xs[i, 1] = 0
        p[i, 1] = 0

        for j in 2:Trials
            xa[i, j] = sum(Y[i, 1:(j - 1)])
            xs[i, j] = j - 1 - xa[i, j]
            p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
            y[i, j] = 1 - Y[i, j]
            y[i, j] ~ dbern(p[i, j])
        end
    end
    alpha ~ dunif(-10, -0.00001)
    beta ~ dunif(-10, -0.00001)
    A = exp(alpha)
    B = exp(beta)
end
```


== JuliaBUGS @model

```julia
@model function dogs((; alpha, beta), Dogs, Trials, Y)
    for i in 1:Dogs
        xa[i, 1] = 0
        xs[i, 1] = 0
        p[i, 1] = 0

        for j in 2:Trials
            xa[i, j] = sum(Y[i, 1:(j - 1)])
            xs[i, j] = j - 1 - xa[i, j]
            p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
            y[i, j] = 1 - Y[i, j]
            y[i, j] ~ dbern(p[i, j])
        end
    end
    alpha ~ dunif(-10, -0.00001)
    beta ~ dunif(-10, -0.00001)
    A = exp(alpha)
    B = exp(beta)
end
```


== BUGS

```julia
model {
    for (i in 1 : Dogs) {
        xa[i, 1] <- 0
        xs[i, 1] <- 0
        p[i, 1] <- 0

        for (j in 2 : Trials) {
            xa[i, j] <- sum(Y[i, 1 : j - 1])
            xs[i, j] <- j - 1 - xa[i, j]
            log(p[i, j]) <- alpha * xa[i, j] + beta * xs[i, j]
            y[i, j] <- 1 - Y[i, j]
            y[i, j] ~ dbern(p[i, j])
        }
    }
    alpha ~ dunif(-10, -0.00001)
    beta ~ dunif(-10, -0.00001)
    A <- exp(alpha)
    B <- exp(beta)
}
```


:::

## How to use this example {#How-to-use-this-example}

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.dogs
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)
```

