# LeukFr: Cox Regression with Random Effects

This example comes from Volume 1 of the classic [BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html), and is also documented on the [OpenBUGS Leukfr page](https://chjackson.github.io/openbugsdoc/Examples/Leukfr.html). The data are the well-known leukaemia remission times of Freireich et al. (1963): 42 patients arranged in 21 matched pairs, where within each pair one patient received the drug 6-mercaptopurine (6-MP) and the other received placebo. For each patient we observe a remission (survival) time `obs.t` and an indicator `fail` of whether the event was observed or the observation was censored, together with a treatment covariate `Z` (coded as ±0.5) and the pairing `pair`.

The question is whether 6-MP prolongs remission, while accounting for the fact that patients were matched in pairs. The model is a Cox proportional-hazards regression fitted through the counting-process (Poisson) representation used throughout the BUGS survival examples. It extends the plain Leuk model by adding a normally distributed **frailty** term `b[pair[i]]`, a random effect shared by the two patients in each matched pair, so that within-pair correlation is modelled explicitly. This is a random-effects (frailty) survival model.

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.leukfr`, which ships with the package.

## Model

At each observed failure time `t[j]` the counting-process increment `dN[i, j]` for patient `i` is treated as Poisson with an intensity that combines the treatment effect, the pair-specific frailty, and a baseline hazard increment `dL0[j]`:

```math
\begin{aligned}
dN_{ij} &\sim \text{Poisson}(I_{ij}) \\
I_{ij} &= Y_{ij}\,\exp(\beta\, Z_i + b_{\text{pair}(i)})\,dL0_j \\
b_k &\sim \text{Normal}(0, \tau) \\
dL0_j &\sim \text{Gamma}(\mu_j, c) \\
\beta &\sim \text{Normal}(0, 10^{-6}) \\
\tau &\sim \text{Gamma}(0.001, 0.001)
\end{aligned}
```

Here `Y[i, j]` is the risk-set indicator (1 if patient `i` is still at risk at time `t[j]`), built from the observed times using `step`. Some variables in the original program have R-style dotted names such as `obs.t`, `dL0.star`, `S.treat`, and `S.placebo`; these are written with Julia's `var"..."` syntax so the names carry over from the original BUGS program unchanged.

```@example leukfr
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.leukfr
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example leukfr
print(example.original_syntax_program)
```

## Data

The data give the study dimensions (`N` = 42 patients, `T` = 17 distinct failure times, `Npairs` = 21 matched pairs), the grid of failure times `t`, the observed remission times `obs.t`, the failure/censoring indicators `fail`, the pair labels `pair`, and the treatment covariate `Z`. We supply them as a `NamedTuple` and construct the model:

```@example leukfr
data = example.data
```

```@example leukfr
inits = example.inits
model = compile(example.model_def, data, inits)
```

We pass the example's published initial values to `compile` rather than compiling from the data alone: this counting-process (Poisson) survival model has vague priors, so values drawn at random from the priors can give an invalid rate, and a sensible starting point keeps construction and sampling stable.

## Sampling

Construct the model with a gradient backend and draw posterior samples with the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data, inits; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    initial_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.leukfr.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censored survival data via the counting-process representation"
    Like the other BUGS survival examples, this model does not handle the censored remission times directly. Instead it uses the counting-process (Poisson) representation: the risk-set indicators `Y[i, j]` and the increments `dN[i, j]` are computed deterministically from the observed times and the `fail` indicator, and the `dN[i, j]` are then treated as Poisson observations. There are no discrete latent variables to sample, so no special handling is required beyond the recipe above.

## Results

The source file ships `reference_results = nothing` for this example, so there is no tabulated reference posterior summary bundled with the package to reproduce here. For published numerical summaries of the treatment effect `beta` and the frailty standard deviation `sigma` (obtained after a 1,000-iteration burn-in followed by 10,000 further updates), see the [OpenBUGS Leukfr page](https://chjackson.github.io/openbugsdoc/Examples/Leukfr.html). A correctly converged chain's `summarystats` output should match those published values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="leukfr"></div>
```

See also: the [gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
