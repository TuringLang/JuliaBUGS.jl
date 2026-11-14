# Oxford: Smooth Fit to Log-Odds Ratios

This example comes from a classic case-control study of childhood cancer and maternal exposure to X-rays during pregnancy, analysed by Breslow and Clayton (1993). The data are arranged as 120 small 2-by-2 tables, one per stratum. Each stratum cross-classifies cases (children who died of cancer) and matched controls by whether the mother received a prenatal X-ray, and the strata are defined by the child's age group and birth-year cohort spanning the years 1944 to 1964. For stratum $i$, `r1[i]` of the `n1[i]` cases were exposed and `r0[i]` of the `n0[i]` controls were exposed, while `year[i]` records the (centred) birth year of that stratum.

The scientific question is whether the association between prenatal X-ray exposure and childhood cancer changed smoothly over the birth years covered by the study. The model is a Bayesian hierarchical binomial (logistic) regression: each stratum gets its own nuisance intercept `mu[i]` for the exposure odds among controls, and the log-odds ratio comparing cases with controls, `logPsi[i]`, is described as a smooth quadratic function of birth year plus a normal random effect that absorbs residual between-stratum variation. It is one of the examples in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Oxford.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.oxford`, which ships with the package.

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

example = JuliaBUGS.BUGSExamples.VOLUME_1.oxford
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example oxford
print(example.original_syntax_program)
```

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="oxford" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data are supplied as a `NamedTuple` with the number of strata `K`, the centred birth year `year` of each stratum, and the exposure counts among cases (`r1` out of `n1`) and among controls (`r0` out of `n0`).

```@example oxford
data = example.data
```

```@example oxford
model = compile(example.model_def, data)
```

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    initial_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.oxford.inits` and can be applied with `initialize!(model, inits)`.

## Results

This transcription does not bundle a numeric reference table (`JuliaBUGS.BUGSExamples.VOLUME_1.oxford.reference_results` is `nothing`), so there is nothing to reproduce verbatim here. For published posterior summaries of $\alpha$, $\beta_1$, $\beta_2$, and $\sigma$, consult the [OpenBUGS Oxford example](https://chjackson.github.io/openbugsdoc/Examples/Oxford.html) and the original analysis by Breslow and Clayton (1993). A correctly converged chain's `summarystats` should agree with those published values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="oxford"></div>
```

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
