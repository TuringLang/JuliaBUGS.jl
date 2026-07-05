# Stacks: Robust Regression

This example comes from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Stacks.html)). It analyses Brownlee's much-studied stack loss data: 21 days of operation of a plant that oxidises ammonia to nitric acid. The response `Y` is the "stack loss" — the amount of ammonia escaping up the stack — and the three covariates in `x` are air flow, cooling water inlet temperature, and acid concentration.

The model is a linear regression of stack loss on the standardised covariates. Because this data set is famous for containing outliers, the original BUGS example uses it to illustrate robust regression: the same linear predictor can be combined with normal, double-exponential, or Student-t(4) error distributions, and each observation gets an `outlier` indicator that flags standardised residuals larger than 2.5 in absolute value. The version shipped with JuliaBUGS uses normal errors; the alternative error distributions (and an exchangeable "ridge regression" prior on the coefficients) appear as comments in the model code, exactly as in the original.

## Model

Writing ``z_{ij}`` for the standardised covariates, the (normal-errors) model is

```math
\begin{aligned}
\mu_i &= \beta_0 + \beta_1 z_{i1} + \beta_2 z_{i2} + \beta_3 z_{i3} \\
Y_i &\sim \text{Normal}(\mu_i, \tau) \qquad i = 1, \ldots, 21
\end{aligned}
```

where, following BUGS convention, ``\tau`` is a precision (``\sigma = 1/\sqrt{\tau}``). The intercept and coefficients get vague normal priors and ``\tau`` gets a vague gamma prior. The coefficients on the original (unstandardised) scale are recovered as `b` and `b0`.

```@example stacks
using JuliaBUGS

stacks = @bugs begin
    # Standardise x's and coefficients
    for j in 1:p
        b[j] = beta[j] / sd(x[:, j])
        for i in 1:N
            z[i, j] = (x[i, j] - mean(x[:, j])) / sd(x[:, j])
        end
    end
    b0 = beta0 - b[1] * mean(x[:, 1]) - b[2] * mean(x[:, 2]) - b[3] * mean(x[:, 3])

    # Model
    d = 4 # degrees of freedom for t
    for i in 1:N
        Y[i] ~ dnorm(mu[i], tau)
        # Y[i] ~ ddexp(mu[i], tau)
        # Y[i] ~ dt(mu[i], tau, d)

        mu[i] = beta0 + beta[1] * z[i, 1] + beta[2] * z[i, 2] + beta[3] * z[i, 3]
        stres[i] = (Y[i] - mu[i]) / sigma
        outlier[i] = step(stres[i] - 2.5) + step(-(stres[i] + 2.5))
    end

    # Priors
    beta0 ~ dnorm(0, 0.00001)
    for j in 1:p
        beta[j] ~ dnorm(0, 0.00001)    # coeffs independent
        # beta[j] ~ dnorm(0, phi) # coeffs exchangeable (ridge regression)
    end
    tau ~ dgamma(1.0E-3, 1.0E-3)
    # phi ~ dgamma(1.0E-2, 1.0E-2)
    # standard deviation of error distribution
    sigma = sqrt(1 / tau) # normal errors
    # sigma <- sqrt(2) / tau # double exponential errors
    # sigma <- sqrt(d / (tau * (d - 2))); # t errors on d degrees of freedom
end
```

## Data

The data are the 21 stack loss measurements `Y` and the 21 x 3 covariate matrix `x` (air flow, temperature, acid concentration), together with the dimensions `N` and `p`. Compiling the model definition with the data produces a runnable model.

```@example stacks
data = (
    p = 3,
    N = 21,
    Y = [42, 37, 37, 28, 18, 18, 19, 20, 15, 14, 14, 13, 11, 12, 8, 7, 8, 8, 9, 15, 15],
    x = [80 27 89
         80 27 88
         75 25 90
         62 24 87
         62 22 87
         62 23 87
         62 24 93
         62 24 93
         58 23 87
         58 18 80
         58 18 89
         58 17 88
         58 18 82
         58 19 93
         50 18 89
         50 18 86
         50 19 72
         50 19 79
         50 20 80
         56 20 82
         70 20 91]
)

model = stacks(data)
```

All the classic Volume 1 examples ship with the package in `JuliaBUGS.BUGSExamples` — this one is `JuliaBUGS.BUGSExamples.VOLUME_1.stacks`, with fields for the model definition, data, initial values, and reference results.

## Sampling

To draw posterior samples, rebuild the model with gradient support and run the NUTS sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = stacks(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.stacks.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter     | Mean   | Std    |
|:------------- |:------ |:------ |
| `b0`          | -39.64 | 12.63  |
| `outlier[21]` | 0.3324 | 0.4711 |

A correctly converged chain's `summarystats` should reproduce these values up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
