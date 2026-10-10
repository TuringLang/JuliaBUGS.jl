# Bones: Latent Trait Model for Multiple Ordered Categorical Responses

This example comes from Volume 1 of the classic [BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS Bones page](https://chjackson.github.io/openbugsdoc/Examples/Bones.html)). It addresses skeletal age assessment: children of the same chronological age can differ widely in physical maturity, so radiographs are scored to estimate how far along each child is in skeletal development. Roche et al. (1975) built a calibration system based on 34 indicators of skeletal maturity that can be read from a radiograph. Each indicator is scored into ordered grades — 19 of them are simply immature/mature (2 grades), while others have 3, 4, or 5 grades — and each indicator comes with two fixed, previously calibrated numbers: a *discriminability* and a set of grade *thresholds*.

The model treats each child's skeletal age as an unknown latent trait and combines the 34 graded indicators to estimate it. This is a latent trait model (equivalently, a graded-response item response model): the probability of scoring above a given threshold on an indicator rises smoothly with the child's skeletal age. The data, from Thissen (1986), cover 13 boys ranging from 6 months to 18 years old, and some of the recorded grades are missing and are treated as further unknowns to be estimated.

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.bones`, which ships with the package.

## Model

Let ``\theta_i`` be the latent skeletal age of child ``i``. For indicator ``j`` with discriminability ``\delta_j`` and thresholds ``\gamma_{jk}``, the cumulative probability of scoring above grade ``k`` is

```math
\begin{aligned}
\theta_i &\sim \text{Normal}(0,\ \tau = 0.001) \\
\text{logit}(Q_{ijk}) &= \delta_j\,(\theta_i - \gamma_{jk}) \\
p_{ijk} &= Q_{ij,k-1} - Q_{ijk} \\
\text{grade}_{ij} &\sim \text{Categorical}(p_{ij})
\end{aligned}
```

where the individual grade probabilities ``p_{ijk}`` are obtained by differencing the cumulative probabilities (with the first and last categories handled at the boundaries). The prior on ``\theta_i`` is a diffuse normal (precision ``0.001``, i.e. variance ``1000``). The model definition as JuliaBUGS holds it, parsed from the BUGS program below:

```@example bones
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.bones
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example bones
print(example.original_syntax_program)
```

## Data

The dataset is a little large to type out, so we load it from the copy that ships with the package:

```@example bones
data = example.data
```

```@example bones
model = compile(example.model_def, data)
```

The data contain `nChild` (13 children) and `nInd` (34 skeletal maturity indicators). For each indicator, `delta` gives the calibrated discriminability, `gamma` gives the grade thresholds, and `ncat` gives the number of grades. The observed scores are held in `grade`, a 13-by-34 matrix in which some entries are missing; those missing scores become additional unknowns that the model estimates alongside the children's skeletal ages.

## Sampling

With the model built, we hand it to a Hamiltonian Monte Carlo sampler; the recipe below constructs the model with gradient support and draws posterior samples.

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

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.bones.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Discrete latent variables"
    The missing entries in `grade` are unobserved ordered-categorical scores, so they are discrete latent variables drawn from `dcat`. Gradient-based samplers such as NUTS cannot move in discrete dimensions directly, so these variables are handled by automatically summing them out (marginalization) before sampling the continuous skeletal ages. See [Auto-Marginalization](../../inference/auto_marginalization.md) for how this works and when it applies.

## Results

This example does not ship with a stored table of reference posterior summaries (`reference_results` is `nothing` in the packaged example), so there is no bundled reference table to reproduce here. The quantities of interest are the 13 latent skeletal ages `theta`, one per child; the published OpenBUGS/MultiBUGS results report their posterior means and standard deviations for comparison. A correctly converged chain's `summarystats` output for `theta` should match those published values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="bones"></div>
```

See also: the [Example Gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
