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

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.salm`, which ships with the package.

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

example = JuliaBUGS.BUGSExamples.VOLUME_1.salm
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example salm
print(example.original_syntax_program)
```

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="salm" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data are small enough to write out in full. `doses` and `plates` give the dimensions of
the count matrix `y` (six doses by three replicate plates), and `x` holds the six dose levels
in µg per plate.

```@example salm
data = example.data
```

```@example salm
model = compile(example.model_def, data)
```

## Sampling

To draw posterior samples, rebuild the model with a gradient backend and run the No-U-Turn
sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data; adtype=AutoMooncake(; config=nothing))

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

```@raw html
<div class="mcmc-run" data-example="salm"></div>
```

See also: the [gallery overview](../index.md) and the
[getting-started tutorial](../../getting_started.md).
