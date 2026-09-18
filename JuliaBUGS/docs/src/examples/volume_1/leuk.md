# Leuk: Cox Regression

This example is the classic leukemia survival dataset, in which the remission times of 42 patients are compared between two treatment groups. In the data each patient carries a treatment covariate `Z` coded as $\pm 0.5$ (21 patients in each group), an observed time `obs.t`, and a failure indicator `fail` that records whether the observed time is a true failure or a right-censored follow-up time. The goal is to estimate the effect of treatment on the hazard of relapse and to recover the survival curve in each group.

The model is a Cox proportional-hazards regression in which the integrated baseline hazard is estimated non-parametrically, following the counting-process formulation of Clayton (1994) using the notation of Andersen and Gill (1982). Rather than fitting a censored survival likelihood directly, the increments of each patient's counting process are treated as independent Poisson variables whose means depend on a risk-set indicator, the treatment effect $\beta$, and the jump $d\Lambda_0$ in the baseline hazard over each time interval; the hazard increments are given a conjugate gamma-process prior. This reformulation looks somewhat indirect, but it lays the groundwork for extensions to frailty models, time-dependent covariates, and smoothed hazards. It is one of the examples in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Leuk.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.leuk`, which ships with the package.

## Model

```math
\begin{aligned}
dN_i(t_j) &\sim \text{Poisson}\left(I_i(t_j)\right) \\
I_i(t_j) &= Y_i(t_j)\, \exp(\beta z_i)\, d\Lambda_0(t_j) \\
d\Lambda_0(t_j) &\sim \text{Gamma}\left(c\, d\Lambda_0^*(t_j),\ c\right) \\
\beta &\sim \text{Normal}(0,\ 10^{-6})
\end{aligned}
```

Here $Y_i(t_j)$ is the risk-set indicator (1 if patient $i$ is still under observation at time $t_j$), $dN_i(t_j)$ counts a failure of patient $i$ in the interval starting at $t_j$, and $d\Lambda_0^*$ is a prior guess at the hazard with $c$ controlling the strength of that guess.

```@example leuk
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.leuk
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example leuk
print(example.original_syntax_program)
```

Names such as `var"obs.t"`, `var"dL0.star"`, `var"S.treat"`, and `var"S.placebo"` are the R-style dotted variable names from the original BUGS program, written with Julia's `var"..."` syntax so they can be kept exactly as they appear in the classic example.

## Data

The data are supplied as a `NamedTuple`: the number of patients `N`, the number of distinct failure times `T`, a small constant `eps` used in the risk-set comparisons, the observed times `obs.t` (in weeks), the failure indicator `fail`, the treatment covariate `Z` (coded $\pm 0.5$), and the grid of interval boundaries `t`.

```@example leuk
data = example.data
```

```@example leuk
model = compile(example.model_def, data, (; beta=0.0))
```

The initial value for `beta` matters here: its prior `dnorm(0.0, 0.000001)` has standard deviation 1000, and a random draw far in the tails overflows `exp(beta * Z[i])` during model construction. Passing a starting value avoids that.

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data, (; beta=0.0); adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.leuk.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censoring is handled by the counting-process formulation"
    This is a survival model with right-censored data: the `fail` indicator marks which observed times are true failures rather than censored follow-up times. Instead of a censored or truncated likelihood, the Cox model is recast in counting-process form, so censoring enters only through the risk-set indicators `Y` and the failure counts `dN`, and the likelihood reduces to an ordinary Poisson model over continuous parameters. No special censoring machinery or discrete latent variables are involved.

## Results

No reference posterior summaries ship with this example in `JuliaBUGS.BUGSExamples`. Published results for the quantities of interest, including the treatment effect `beta` and the survivor functions `S.treat` and `S.placebo`, are available on the [OpenBUGS page for this example](https://chjackson.github.io/openbugsdoc/Examples/Leuk.html), and a correctly converged chain's `summarystats` should reproduce them up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="leuk"></div>
```

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
