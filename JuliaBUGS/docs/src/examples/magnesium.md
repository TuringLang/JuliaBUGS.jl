# Magnesium: Sensitivity to Prior Distributions in Meta-Analysis

This example is a random-effects meta-analysis of eight randomised clinical trials of intravenous magnesium sulphate following acute myocardial infarction. Each trial reports the number of deaths in the magnesium arm (`rt` out of `nt` patients) and in the control arm (`rc` out of `nc` patients), and the quantity of interest is the pooled odds ratio of death under treatment versus control. It comes from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); the matching OpenBUGS documentation page is [here](https://chjackson.github.io/openbugsdoc/Examples/Magnesium.html).

With only eight studies, the data carry little information about the between-study heterogeneity, so posterior conclusions can be sensitive to the prior placed on the heterogeneity parameter. The model therefore fits the same hierarchical binomial–logistic meta-analysis six times in parallel, once under each of six alternative priors on the between-study variance ``\tau^2``: a Gamma(0.001, 0.001) prior on the precision, uniform priors on ``\tau^2`` and on ``\tau``, a uniform-shrinkage prior, a DuMouchel prior, and a half-normal prior. Comparing the six fits shows how much the pooled odds ratio and the heterogeneity estimate depend on that choice.

## Model

For prior ``j = 1, \dots, 6`` and study ``k = 1, \dots, 8``:

```math
\begin{aligned}
r^c_k &\sim \text{Binomial}(n^c_k,\, p^c_{jk}), \qquad
r^t_k \sim \text{Binomial}(n^t_k,\, p^t_{jk}) \\
\operatorname{logit}(p^t_{jk}) &= \theta_{jk} + \operatorname{logit}(p^c_{jk}) \\
\theta_{jk} &\sim \text{Normal}(\mu_j,\, \tau_j^2), \qquad
\text{OR}_j = e^{\mu_j}
\end{aligned}
```

where ``\theta_{jk}`` is the log-odds ratio in study ``k``, ``\mu_j`` is the pooled log-odds ratio under prior ``j``, and ``\tau_j^2`` is the between-study variance, whose prior differs across ``j``. Names such as `var"odds.ratio"` and `var"inv.tau.sqrd"` are the R-style dotted names from the original BUGS program, written with Julia's `var"..."` syntax. The pair of statements assigning `rtx[j, k]` both a distribution and the observed value `rt[k]` (and likewise `rcx[j, k]`) is the standard BUGS device for feeding the same observed data into all six sub-models.

```@example magnesium
using JuliaBUGS
using Distributions

# `truncated` comes from Distributions; make it available inside `@bugs`:
JuliaBUGS.@bugs_primitive truncated

magnesium = @bugs begin
    # j indexes alternative prior distributions
    for j in 1:6
        mu[j] ~ dunif(-10, 10)
        var"odds.ratio"[j] = exp(mu[j])

        # k indexes study number
        for k in 1:8
            theta[j, k] ~ dnorm(mu[j], var"inv.tau.sqrd"[j])
            rtx[j, k] ~ dbin(pt[j, k], nt[k])
            rtx[j, k] = rt[k]
            rcx[j, k] ~ dbin(pc[j, k], nc[k])
            rcx[j, k] = rc[k]
            pt[j, k] = logistic(theta[j, k] + phi[j, k])
            phi[j, k] = logit(pc[j, k])
            pc[j, k] ~ dunif(0, 1)
        end
    end

    # k again indexes study number
    for k in 1:8
        # log-odds ratios:
        y[k] = log(((rt[k] + 0.5) / (nt[k] - rt[k] + 0.5)) /
                   ((rc[k] + 0.5) / (nc[k] - rc[k] + 0.5)))
        # variances & precisions:
        var"sigma.sqrd"[k] = 1 / (rt[k] + 0.5) + 1 / (nt[k] - rt[k] + 0.5) +
                             1 / (rc[k] + 0.5) +
                             1 / (nc[k] - rc[k] + 0.5)
        var"prec.sqrd"[k] = 1 / var"sigma.sqrd"[k]
    end
    var"s0.sqrd" = 1 / mean(var"prec.sqrd"[1:8])

    # Prior 1: Gamma(0.001, 0.001) on inv.tau.sqrd
    var"inv.tau.sqrd"[1] ~ dgamma(0.001, 0.001)
    var"tau.sqrd"[1] = 1 / var"inv.tau.sqrd"[1]
    tau[1] = sqrt(var"tau.sqrd"[1])

    # Prior 2: Uniform(0, 50) on tau.sqrd
    var"tau.sqrd"[2] ~ dunif(0, 50)
    tau[2] = sqrt(var"tau.sqrd"[2])
    var"inv.tau.sqrd"[2] = 1 / var"tau.sqrd"[2]

    # Prior 3: Uniform(0, 50) on tau
    tau[3] ~ dunif(0, 50)
    var"tau.sqrd"[3] = tau[3] * tau[3]
    var"inv.tau.sqrd"[3] = 1 / var"tau.sqrd"[3]

    # Prior 4: Uniform shrinkage on tau.sqrd
    B0 ~ dunif(0, 1)
    var"tau.sqrd"[4] = var"s0.sqrd" * (1 - B0) / B0
    tau[4] = sqrt(var"tau.sqrd"[4])
    var"inv.tau.sqrd"[4] = 1 / var"tau.sqrd"[4]

    # Prior 5: Dumouchel on tau
    D0 ~ dunif(0, 1)
    tau[5] = sqrt(var"s0.sqrd") * (1 - D0) / D0
    var"tau.sqrd"[5] = tau[5] * tau[5]
    var"inv.tau.sqrd"[5] = 1 / var"tau.sqrd"[5]

    # Prior 6: Half-Normal on tau.sqrd
    p0 = phi(0.75) / var"s0.sqrd"
    var"tau.sqrd"[6] ~ truncated(dnorm(0, p0), 0, nothing)
    tau[6] = sqrt(var"tau.sqrd"[6])
    var"inv.tau.sqrd"[6] = 1 / var"tau.sqrd"[6]
end
```

## Data

The data are the observed death counts and group sizes from the eight trials: `rt` and `nt` are the deaths and number of patients in the magnesium arm, and `rc` and `nc` are the same for the control arm.

```@example magnesium
data = (
    rt = [1, 9, 2, 1, 10, 1, 1, 90],
    nt = [40, 135, 200, 48, 150, 59, 25, 1159],
    rc = [2, 23, 7, 1, 8, 9, 3, 118],
    nc = [36, 135, 200, 46, 148, 56, 23, 1157]
)
model = magnesium(data)
```

All the classic examples ship with the package: `JuliaBUGS.BUGSExamples.VOLUME_1.magnesium` bundles the model definition, data, initial values, and reference results, so you can also load everything from there instead of typing it in.

## Sampling

To draw posterior samples, rebuild the model with gradient support and run the NUTS sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = magnesium(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.magnesium.inits` and can be applied with `initialize!(model, inits)`.

!!! note
    Prior 6 places a half-normal prior on the between-study variance. The original BUGS program writes this as `dnorm(0, p0)T(0,)`; in JuliaBUGS the same truncated prior is written `truncated(dnorm(0, p0), 0, nothing)`, where `nothing` means the upper bound is left unbounded. This affects only the prior on `var"tau.sqrd"[6]` — no observed data are censored or truncated.

## Results

The package does not bundle reference posterior summaries for this example (its `reference_results` field is empty): the point of the exercise is to compare results across the six priors rather than to reproduce a single set of numbers. Published summaries of `odds.ratio[1:6]` and `tau[1:6]` under each prior are shown on the [OpenBUGS Magnesium page](https://chjackson.github.io/openbugsdoc/Examples/Magnesium.html), and a correctly converged chain's `summarystats(chain)` should match them up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
