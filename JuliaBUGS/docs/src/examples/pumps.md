# Pumps: Conjugate Gamma-Poisson Hierarchical Model

This example concerns failure records for 10 power plant pumps. For each pump we know how long it operated (in thousands of hours) and how many failures it experienced over that period. The question is how to estimate a failure rate for each individual pump: some pumps ran for only about a thousand hours, so their raw failure counts are very noisy on their own. A hierarchical model answers this by assuming the pump-specific failure rates are drawn from a common gamma distribution, so that every pump's estimate borrows strength from the others.

The failure counts are modeled as Poisson, and because the gamma prior on the rates is conjugate to the Poisson likelihood, this is the classic conjugate gamma-Poisson hierarchical model. It is one of the examples from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); the original write-up is also available in the [OpenBUGS documentation](https://chjackson.github.io/openbugsdoc/Examples/Pumps.html).

## Model

For pump ``i`` with operation time ``t_i`` and failure count ``x_i``:

```math
\begin{aligned}
x_i &\sim \text{Poisson}(\theta_i \, t_i), \qquad i = 1, \ldots, N \\
\theta_i &\sim \text{Gamma}(\alpha, \beta) \\
\alpha &\sim \text{Exponential}(1) \\
\beta &\sim \text{Gamma}(0.1, 1.0)
\end{aligned}
```

In JuliaBUGS the model is written with the `@bugs` macro, which accepts the BUGS program almost unchanged:

```@example pumps
using JuliaBUGS

pumps = @bugs begin
    for i in 1:N
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] = theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    end
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
end
```

## Data

The data are a `NamedTuple` with the operation times `t` (thousands of hours), the observed failure counts `x`, and the number of pumps `N`. Calling the model definition with the data builds the model:

```@example pumps
data = (
    t = [94.3, 15.7, 62.9, 126, 5.24, 31.4, 1.05, 1.05, 2.1, 10.5],
    x = [5, 1, 5, 14, 3, 19, 1, 1, 4, 22],
    N = 10
)

model = pumps(data)
```

All of the classic Volume 1 examples ship with the package in `JuliaBUGS.BUGSExamples` — for each example you get the model definition, the data, the initial values, and (where recorded) the reference results; this one is `JuliaBUGS.BUGSExamples.VOLUME_1.pumps`.

## Sampling

To draw posterior samples, rebuild the model with gradient support and run the NUTS sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = pumps(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.pumps.inits` and can be applied with `initialize!(model, inits)`.

## Results

Reference posterior summaries are not bundled with the package for this example; the published results table can be found on the [OpenBUGS Pumps page](https://chjackson.github.io/openbugsdoc/Examples/Pumps.html). The quantities of interest are the hyperparameters `alpha` and `beta` and the pump-specific failure rates `theta[1]` through `theta[10]`. A correctly converged chain's `summarystats(chain)` should match the published values up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
