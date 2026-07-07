# Surgical: Institutional Ranking

This example concerns mortality rates in 12 hospitals performing cardiac surgery in babies. For each hospital ``i`` we observe the number of operations ``n_i`` and the number of deaths ``r_i``, and we want to estimate each hospital's underlying mortality rate — and ultimately to rank the institutions. It is a classic problem in institutional comparison ("league tables"), and it comes from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS documentation page](https://chjackson.github.io/openbugsdoc/Examples/Surgical.html)).

The example fits two models to the same data. The first treats the hospitals as completely independent, giving each mortality probability its own uniform Beta prior. The second, more realistic model is hierarchical: the log-odds of mortality are drawn from a common normal population distribution, so the hospitals share information and each estimate is shrunk towards the population mean. Comparing the two shows the effect of partial pooling — for instance, hospital 1 records 0 deaths in 47 operations, and the hierarchical model tempers the implausibly optimistic estimate the independent model gives it.

## Model

### Independent binomial model

Each hospital gets its own mortality probability with a flat prior, and the death counts are binomial:

```math
\begin{aligned}
p_i &\sim \text{Beta}(1, 1) \\
r_i &\sim \text{Binomial}(n_i, p_i), \quad i = 1, \ldots, N
\end{aligned}
```

```@example surgical_simple
using JuliaBUGS

surgical_simple = @bugs begin
    for i in 1:N
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    end
end
```

### Hierarchical (random effects) model

The realistic model places the hospitals on a common logistic scale: each hospital's log-odds of death ``b_i`` is drawn from a normal population distribution with mean ``\mu`` and precision ``\tau``, with vague priors on the population parameters:

```math
\begin{aligned}
b_i &\sim \text{Normal}(\mu, \sigma^2) \\
\operatorname{logit}(p_i) &= b_i \\
r_i &\sim \text{Binomial}(n_i, p_i) \\
\mu &\sim \text{Normal}(0, 10^6), \qquad \tau = 1/\sigma^2 \sim \text{Gamma}(0.001, 0.001)
\end{aligned}
```

The original BUGS program uses the R-style dotted name `pop.mean` for the population-average mortality rate; in Julia such names are written with the `var"pop.mean"` syntax, which simply declares a variable whose name contains a dot.

```@example surgical_realistic
using JuliaBUGS

surgical_realistic = @bugs begin
    for i in 1:N
        b[i] ~ dnorm(mu, tau)
        r[i] ~ dbin(p[i], n[i])
        p[i] = logistic(b[i])
    end
    var"pop.mean" = exp(mu) / (1 + exp(mu))
    mu ~ dnorm(0.0, 1.0e-6)
    sigma = 1 / sqrt(tau)
    tau ~ dgamma(0.001, 0.001)
end
```

## Data

Both models use the same data: the number of operations `n` and the number of deaths `r` in each of the `N = 12` hospitals. Compiling the independent model is a single call with the data as a `NamedTuple`:

```@example surgical_simple
data = (
    n = [47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
    r = [0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
    N = 12
)

model = surgical_simple(data)
```

The hierarchical model compiles against the identical data:

```@example surgical_realistic
data = (
    n = [47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
    r = [0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
    N = 12
)

model = surgical_realistic(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`: this page's two variants are available as `JuliaBUGS.BUGSExamples.VOLUME_1.surgical_simple` and `JuliaBUGS.BUGSExamples.VOLUME_1.surgical_realistic`, each bundling the model definition, data, initial values, and (where available) reference results.

## Sampling

The same recipe draws posterior samples for either model — here we rebuild the hierarchical model with gradient support and hand it to the NUTS sampler (swap in `surgical_simple` for the independent model):

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = surgical_realistic(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for the hierarchical model are available as `JuliaBUGS.BUGSExamples.VOLUME_1.surgical_realistic.inits` (and `...surgical_simple.inits` for the independent model) and can be applied with `initialize!(model, inits)`.

## Results

The bundled copies of this example do not include reference posterior summaries, so there is no shipped table to compare against here. Published posterior summaries for both models — the per-hospital mortality rates `p[1]` through `p[12]`, and for the hierarchical model also `mu`, `sigma`, and `pop.mean` — are given on the [OpenBUGS Surgical page](https://chjackson.github.io/openbugsdoc/Examples/Surgical.html). A correctly converged chain's `summarystats` should reproduce those values up to Monte Carlo error, with the hierarchical estimates visibly shrunk towards the population mean relative to the independent ones.

*See also:* the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
