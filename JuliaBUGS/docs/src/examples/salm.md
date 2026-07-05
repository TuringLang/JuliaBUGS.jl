# Salm: Extra-Poisson Variation in Dose-Response Study

This is the **Salm** example from Volume 1 of the classic BUGS examples
([overview](https://www.multibugs.org/examples/latest/VolumeI.html), and the matching
[OpenBUGS page](https://chjackson.github.io/openbugsdoc/Examples/Salm.html)). The data come
from a *Salmonella* mutagenicity assay reported by Breslow (1984): plates of TA98
*Salmonella* bacteria are exposed to the mutagen quinoline at six increasing doses
(0, 10, 33, 100, 333 and 1000 µg per plate), with three replicate plates at each dose, and
the number of revertant colonies on each plate is counted. The scientific question is how
the colony count depends on the dose.

The counts are modeled as Poisson, but they show more variability than a plain Poisson model
allows — the "extra-Poisson variation" of the title. To capture this overdispersion, the
model adds a plate-level normal random effect on the log scale. The dose enters the log-mean
through both a `log(dose + 10)` term (the offset of 10 keeps the term finite at the zero
dose) and a linear dose term, so this is a log-linear Poisson regression with random effects
— a Poisson–lognormal model.

## Model

```math
\begin{aligned}
y_{ij} &\sim \text{Poisson}(\mu_{ij}) \\
\log \mu_{ij} &= \alpha + \beta \log(x_i + 10) + \gamma\, x_i + \lambda_{ij} \\
\lambda_{ij} &\sim \text{Normal}(0, \tau) \\
\alpha, \beta, \gamma &\sim \text{Normal}(0, 10^{-6}) \\
\tau &\sim \text{Gamma}(0.001, 0.001), \qquad \sigma = 1 / \sqrt{\tau}
\end{aligned}
```

Following the BUGS convention, the second argument of the normal distribution is the
*precision* (the reciprocal of the variance): the priors on `alpha`, `beta` and `gamma` are
therefore extremely vague, and each plate effect `lambda[i, j]` has precision `tau`.

```@example salm
using JuliaBUGS

salm = @bugs begin
    for i in 1:doses
        for j in 1:plates
            y[i, j] ~ dpois(mu[i, j])
            mu[i, j] = exp(alpha + beta * log(x[i] + 10) + gamma * x[i] + lambda[i, j])
            lambda[i, j] ~ dnorm(0.0, tau)
        end
    end
    alpha ~ dnorm(0.0, 1.0e-6)
    beta ~ dnorm(0.0, 1.0e-6)
    gamma ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

## Data

The data are small enough to write out in full. `doses` and `plates` give the dimensions of
the count matrix `y` (six doses by three replicate plates), and `x` holds the six dose levels
in µg per plate.

```@example salm
data = (
    doses = 6,
    plates = 3,
    y = [15 21 29;
         16 18 21;
         16 26 33;
         27 41 60;
         33 38 41;
         20 27 42],
    x = [0, 10, 33, 100, 333, 1000]
)

model = salm(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples` — each entry
bundles the model definition, the data, a set of initial values, and (where available)
reference results.

## Sampling

To draw posterior samples, rebuild the model with a gradient backend and run the No-U-Turn
sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = salm(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as
`JuliaBUGS.BUGSExamples.VOLUME_1.salm.inits` and can be applied with
`initialize!(model, inits)`.

## Results

Unlike most entries in this gallery, the Salm example does not ship with bundled reference
posterior summaries — its `reference_results` field is empty, so there is no packaged table
to reproduce here. The published Bayesian posterior summaries for this model are given on the
[MultiBUGS](https://www.multibugs.org/examples/latest/VolumeI.html) and
[OpenBUGS](https://chjackson.github.io/openbugsdoc/Examples/Salm.html) pages linked above
(obtained there from a 1000-iteration burn-in followed by 10000 further iterations).

For a rough sanity check, the OpenBUGS page also quotes Breslow's (1984) quasi-likelihood
point estimates:

| Parameter | Estimate | Std. error |
| --- | --- | --- |
| alpha | 2.203 | 0.363 |
| beta | 0.311 | 0.099 |
| gamma | -9.74e-4 | 4.37e-4 |
| sigma | 0.268 | — |

These are maximum quasi-likelihood point estimates rather than posterior summaries, but the
posterior means from a correctly converged chain should land close to them, up to Monte Carlo
error and the mild differences between the two estimation approaches.

See also: the [gallery overview](index.md) and the
[getting-started tutorial](../getting_started.md).
