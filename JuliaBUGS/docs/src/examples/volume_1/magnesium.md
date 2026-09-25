# Magnesium: Sensitivity to Prior Distributions in Meta-Analysis

This example is a random-effects meta-analysis of eight randomised clinical trials of intravenous magnesium sulphate following acute myocardial infarction. Each trial reports the number of deaths in the magnesium arm (`rt` out of `nt` patients) and in the control arm (`rc` out of `nc` patients), and the quantity of interest is the pooled odds ratio of death under treatment versus control. It comes from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); the matching OpenBUGS documentation page is [here](https://chjackson.github.io/openbugsdoc/Examples/Magnesium.html).

With only eight studies, the data carry little information about the between-study heterogeneity, so posterior conclusions can be sensitive to the prior placed on the heterogeneity parameter. The model therefore fits the same hierarchical binomial–logistic meta-analysis six times in parallel, once under each of six alternative priors on the between-study variance ``\tau^2``: a Gamma(0.001, 0.001) prior on the precision, uniform priors on ``\tau^2`` and on ``\tau``, a uniform-shrinkage prior, a DuMouchel prior, and a half-normal prior. Comparing the six fits shows how much the pooled odds ratio and the heterogeneity estimate depend on that choice.

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.magnesium`, which ships with the package.

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

example = JuliaBUGS.BUGSExamples.VOLUME_1.magnesium
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example magnesium
print(example.original_syntax_program)
```

## Data

The data are the observed death counts and group sizes from the eight trials: `rt` and `nt` are the deaths and number of patients in the magnesium arm, and `rc` and `nc` are the same for the control arm.

```@example magnesium
data = example.data
```

```@example magnesium
model = compile(example.model_def, data)
```

## Sampling

To draw posterior samples, rebuild the model with gradient support and run the NUTS sampler:

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

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.magnesium.inits` and can be applied with `initialize!(model, inits)`.

!!! note
    Prior 6 places a half-normal prior on the between-study variance. The original BUGS program writes this as `dnorm(0, p0)T(0,)`; in JuliaBUGS the same truncated prior is written `truncated(dnorm(0, p0), 0, nothing)`, where `nothing` means the upper bound is left unbounded. This affects only the prior on `var"tau.sqrd"[6]` — no observed data are censored or truncated.

## Results

The package does not bundle reference posterior summaries for this example (its `reference_results` field is empty): the point of the exercise is to compare results across the six priors rather than to reproduce a single set of numbers. Published summaries of `odds.ratio[1:6]` and `tau[1:6]` under each prior are shown on the [OpenBUGS Magnesium page](https://chjackson.github.io/openbugsdoc/Examples/Magnesium.html), and a correctly converged chain's `summarystats(chain)` should match them up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="magnesium"></div>
```

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
