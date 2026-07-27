# Dyes: Variance Components Model

The Dyes example, from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html), analyses data on the yield of dyestuff from a chemical process, originally presented by Davies (1967) and discussed by Box and Tiao (1973). Five samples were taken from each of six randomly chosen batches of raw material, and the total product yield was recorded for each sample. The scientific question is how much of the variation in yield is due to differences *between* batches and how much is ordinary sampling and measurement variation *within* a batch.

The model is a one-way random effects (variance components) model: each measurement varies normally around its batch mean, and the batch means themselves vary normally around an overall mean yield. Comparing the two variance components tells us whether batch-to-batch differences matter relative to within-batch noise. A fuller description is available on the [OpenBUGS Dyes page](https://chjackson.github.io/openbugsdoc/Examples/Dyes.html).

## Model

Writing ``\sigma^2_{\text{with}}`` and ``\sigma^2_{\text{btw}}`` for the within-batch and between-batch variances, the model is

```math
\begin{aligned}
y_{ij} &\sim \text{Normal}(\mu_i,\ \sigma^2_{\text{with}}), & i &= 1,\dots,6;\ j = 1,\dots,5, \\
\mu_i &\sim \text{Normal}(\theta,\ \sigma^2_{\text{btw}}),
\end{aligned}
```

with a vague normal prior on the overall mean ``\theta`` and vague gamma priors on the two precisions (BUGS parameterises the normal distribution by its precision, the reciprocal of the variance).

```@example dyes
using JuliaBUGS

dyes = @bugs begin
    for i in 1:batches
        mu[i] ~ dnorm(theta, var"tau.btw")
        for j in 1:samples
            y[i, j] ~ dnorm(mu[i], var"tau.with")
        end
    end
    var"sigma2.with" = 1 / var"tau.with"
    var"sigma2.btw" = 1 / var"tau.btw"
    var"tau.with" ~ dgamma(0.001, 0.001)
    var"tau.btw" ~ dgamma(0.001, 0.001)
    theta ~ dnorm(0.0, 1.0e-10)
end
```

Names such as `var"tau.btw"` are the R-style dotted names from the original BUGS program (`tau.btw`), written with Julia's `var"..."` syntax so the dot can be kept in the variable name.

## Data

The data are the 30 yield measurements (in grams of standard colour), arranged as a 6 × 5 matrix with one row per batch.

```@example dyes
data = (
    batches = 6,
    samples = 5,
    y = [1545 1440 1440 1520 1580
         1540 1555 1490 1560 1495
         1595 1550 1605 1510 1560
         1445 1440 1595 1465 1545
         1595 1630 1515 1635 1625
         1520 1455 1450 1480 1445]
)

model = dyes(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`: for this example, `JuliaBUGS.BUGSExamples.VOLUME_1.dyes` bundles the model definition, data, initial values, and reference results.

## Sampling

To draw posterior samples, build the model with gradient support and run the NUTS sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = dyes(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.dyes.inits` and can be applied with `initialize!(model, inits)`.

## Results

No reference posterior table is bundled with this example (`JuliaBUGS.BUGSExamples.VOLUME_1.dyes.reference_results` is `nothing`), so compare your output against the published summaries on the [OpenBUGS Dyes page](https://chjackson.github.io/openbugsdoc/Examples/Dyes.html). As points of reference, the classical analysis of these data gives ``\sigma^2_{\text{with}} = 2451`` and ``\sigma^2_{\text{btw}} = 1764``, and the overall mean yield ``\theta`` is close to the sample grand mean of about 1527. Note that the posterior of the between-batch variance has a very long upper tail, so its posterior mean sits well above its median; a correctly converged chain's `summarystats` should agree with the published BUGS results up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
