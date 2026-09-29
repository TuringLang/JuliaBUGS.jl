# Dyes: Variance Components Model

The Dyes example, from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html), analyses data on the yield of dyestuff from a chemical process, originally presented by Davies (1967) and discussed by Box and Tiao (1973). Five samples were taken from each of six randomly chosen batches of raw material, and the total product yield was recorded for each sample. The scientific question is how much of the variation in yield is due to differences *between* batches and how much is ordinary sampling and measurement variation *within* a batch.

The model is a one-way random effects (variance components) model: each measurement varies normally around its batch mean, and the batch means themselves vary normally around an overall mean yield. Comparing the two variance components tells us whether batch-to-batch differences matter relative to within-batch noise. A fuller description is available on the [OpenBUGS Dyes page](https://chjackson.github.io/openbugsdoc/Examples/Dyes.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.dyes`, which ships with the package.

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

example = JuliaBUGS.BUGSExamples.VOLUME_1.dyes
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example dyes
print(example.original_syntax_program)
```

Names such as `var"tau.btw"` are the R-style dotted names from the original BUGS program (`tau.btw`), written with Julia's `var"..."` syntax so the dot can be kept in the variable name.

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="dyes" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data are the 30 yield measurements (in grams of standard colour), arranged as a 6 × 5 matrix with one row per batch.

```@example dyes
data = example.data
```

```@example dyes
model = compile(example.model_def, data)
```

## Sampling

To draw posterior samples, build the model with gradient support and run the NUTS sampler:

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

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.dyes.inits` and can be applied with `initialize!(model, inits)`.

## Results

No reference posterior table is bundled with this example (`JuliaBUGS.BUGSExamples.VOLUME_1.dyes.reference_results` is `nothing`), so compare your output against the published summaries on the [OpenBUGS Dyes page](https://chjackson.github.io/openbugsdoc/Examples/Dyes.html). As points of reference, the classical analysis of these data gives ``\sigma^2_{\text{with}} = 2451`` and ``\sigma^2_{\text{btw}} = 1764``, and the overall mean yield ``\theta`` is close to the sample grand mean of about 1527. Note that the posterior of the between-batch variance has a very long upper tail, so its posterior mean sits well above its median; a correctly converged chain's `summarystats` should agree with the published BUGS results up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="dyes"></div>
```

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
