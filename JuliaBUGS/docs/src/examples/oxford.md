# Oxford: Smooth Fit to Log-Odds Ratios

This example comes from a classic case-control study of childhood cancer and maternal exposure to X-rays during pregnancy, analysed by Breslow and Clayton (1993). The data are arranged as 120 small 2-by-2 tables, one per stratum. Each stratum cross-classifies cases (children who died of cancer) and matched controls by whether the mother received a prenatal X-ray, and the strata are defined by the child's age group and birth-year cohort spanning the years 1944 to 1964. For stratum $i$, `r1[i]` of the `n1[i]` cases were exposed and `r0[i]` of the `n0[i]` controls were exposed, while `year[i]` records the (centred) birth year of that stratum.

The scientific question is whether the association between prenatal X-ray exposure and childhood cancer changed smoothly over the birth years covered by the study. The model is a Bayesian hierarchical binomial (logistic) regression: each stratum gets its own nuisance intercept `mu[i]` for the exposure odds among controls, and the log-odds ratio comparing cases with controls, `logPsi[i]`, is described as a smooth quadratic function of birth year plus a normal random effect that absorbs residual between-stratum variation. It is one of the examples in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Oxford.html).

## Model

```math
\begin{aligned}
r0_i &\sim \text{Binomial}(n0_i,\ p0_i), & \text{logit}(p0_i) &= \mu_i \\
r1_i &\sim \text{Binomial}(n1_i,\ p1_i), & \text{logit}(p1_i) &= \mu_i + \log\!\Psi_i \\
\log\!\Psi_i &= \alpha + \beta_1\, \text{year}_i + \beta_2\, (\text{year}_i^2 - 22) + b_i \\
b_i &\sim \text{Normal}(0, \tau) \\
\mu_i &\sim \text{Normal}(0, 10^{-6})
\end{aligned}
```

The population parameters $\alpha$, $\beta_1$, $\beta_2$ are given "noninformative" normal priors, $\tau$ a `Gamma(0.001, 0.001)` prior, and $\sigma = 1/\sqrt{\tau}$ is the random-effect standard deviation. Here $\tau$ denotes the precision (inverse variance) of a normal distribution, following the BUGS convention.

```@example oxford
using JuliaBUGS

oxford = @bugs begin
    for i in 1:K
        r0[i] ~ dbin(p0[i], n0[i])
        r1[i] ~ dbin(p1[i], n1[i])
        p0[i] = logistic(mu[i])
        p1[i] = logistic(mu[i] + logPsi[i])
        logPsi[i] = alpha + beta1 * year[i] + beta2 * (year[i] * year[i] - 22) + b[i]
        b[i] ~ dnorm(0, tau)
        mu[i] ~ dnorm(0.0, 1.0e-6)
    end
    alpha ~ dnorm(0.0, 1.0e-6)
    beta1 ~ dnorm(0.0, 1.0e-6)
    beta2 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

## Data

The data are supplied as a `NamedTuple` with the number of strata `K`, the centred birth year `year` of each stratum, and the exposure counts among cases (`r1` out of `n1`) and among controls (`r0` out of `n0`).

```@example oxford
data = (
    r1 = [3, 5, 2, 7, 7, 2, 5, 3, 5, 11, 6, 6, 11, 4, 4, 2, 8, 8, 6, 5, 15, 4, 9, 9, 4,
        12, 8, 8, 6, 8, 12, 4, 7, 16, 12, 9, 4, 7, 8, 11, 5, 12, 8, 17, 9, 3, 2, 7, 6,
        5, 11, 14, 13, 8, 6, 4, 8, 4, 8, 7, 15, 15, 9, 9, 5, 6, 3, 9, 12, 14, 16, 17,
        8, 8, 9, 5, 9, 11, 6, 14, 21, 16, 6, 9, 8, 9, 8, 4, 11, 11, 6, 9, 4, 4, 9, 9,
        10, 14, 6, 3, 4, 6, 10, 4, 3, 3, 10, 4, 10, 5, 4, 3, 13, 1, 7, 5, 7, 6, 3, 7],
    n1 = [28, 21, 32, 35, 35, 38, 30, 43, 49, 53, 31, 35, 46, 53, 61, 40, 29, 44, 52, 55,
        61, 31, 48, 44, 42, 53, 56, 71, 43, 43, 43, 40, 44, 70, 75, 71, 37, 31, 42, 46,
        47, 55, 63, 91, 43, 39, 35, 32, 53, 49, 75, 64, 69, 64, 49, 29, 40, 27, 48, 43,
        61, 77, 55, 60, 46, 28, 33, 32, 46, 57, 56, 78, 58, 52, 31, 28, 46, 42, 45, 63,
        71, 69, 43, 50, 31, 34, 54, 46, 58, 62, 52, 41, 34, 52, 63, 59, 88, 62, 47, 53,
        57, 74, 68, 61, 45, 45, 62, 73, 53, 39, 45, 51, 55, 41, 53, 51, 42, 46, 54, 32],
    r0 = [0, 2, 2, 1, 2, 0, 1, 1, 1, 2, 4, 4, 2, 1, 7, 4, 3, 5, 3, 2, 4, 1, 4, 5, 2,
        7, 5, 8, 2, 3, 5, 4, 1, 6, 5, 11, 5, 2, 5, 8, 5, 6, 6, 10, 7, 5, 5, 2, 8,
        1, 13, 9, 11, 9, 4, 4, 8, 6, 8, 6, 8, 14, 6, 5, 5, 2, 4, 2, 9, 5, 6, 7,
        5, 10, 3, 2, 1, 7, 9, 13, 9, 11, 4, 8, 2, 3, 7, 4, 7, 5, 6, 6, 5, 6, 9, 7,
        7, 7, 4, 2, 3, 4, 10, 3, 4, 2, 10, 5, 4, 5, 4, 6, 5, 3, 2, 2, 4, 6, 4, 1],
    n0 = [28, 21, 32, 35, 35, 38, 30, 43, 49, 53, 31, 35, 46, 53, 61, 40, 29, 44, 52, 55,
        61, 31, 48, 44, 42, 53, 56, 71, 43, 43, 43, 40, 44, 70, 75, 71, 37, 31, 42, 46,
        47, 55, 63, 91, 43, 39, 35, 32, 53, 49, 75, 64, 69, 64, 49, 29, 40, 27, 48, 43,
        61, 77, 55, 60, 46, 28, 33, 32, 46, 57, 56, 78, 58, 52, 31, 28, 46, 42, 45, 63,
        71, 69, 43, 50, 31, 34, 54, 46, 58, 62, 52, 41, 34, 52, 63, 59, 88, 62, 47, 53,
        57, 74, 68, 61, 45, 45, 62, 73, 53, 39, 45, 51, 55, 41, 53, 51, 42, 46, 54, 32],
    year = [
        -10, -9, -9, -8, -8, -8, -7, -7, -7, -7, -6, -6, -6, -6, -6, -5, -5, -5, -5, -5, -5,
        -4, -4, -4, -4, -4, -4, -4, -3, -3, -3, -3, -3, -3, -3, -3, -2, -2, -2, -2, -2, -2,
        -2, -2, -2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 4,
        4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 9, 9, 10],
    K = 120
)

model = oxford(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`, so the model definition, data, initial values, and reference results are also available directly as `JuliaBUGS.BUGSExamples.VOLUME_1.oxford`.

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = oxford(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.oxford.inits` and can be applied with `initialize!(model, inits)`.

## Results

This transcription does not bundle a numeric reference table (`JuliaBUGS.BUGSExamples.VOLUME_1.oxford.reference_results` is `nothing`), so there is nothing to reproduce verbatim here. For published posterior summaries of $\alpha$, $\beta_1$, $\beta_2$, and $\sigma$, consult the [OpenBUGS Oxford example](https://chjackson.github.io/openbugsdoc/Examples/Oxford.html) and the original analysis by Breslow and Clayton (1993). A correctly converged chain's `summarystats` should agree with those published values up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
