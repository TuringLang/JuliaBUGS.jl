# Epilepsy: Repeated Measures on Poisson Counts

Breslow and Clayton (1993) analysed data originally reported by Thall and Vail (1990) on seizure counts from a randomised trial of anti-convulsant therapy in epilepsy. Fifty-nine patients were followed over four successive clinic visits, and the number of seizures in the interval before each visit was recorded, along with each patient's treatment assignment, baseline seizure count, and age. The question is whether the treatment reduces the seizure rate after adjusting for these covariates.

The model is a Poisson generalised linear mixed model (model III of Breslow and Clayton). The log seizure rate is a linear function of centred covariates — log baseline count, treatment, a treatment-by-baseline interaction, log age, and an indicator for the fourth visit — plus a subject-level random effect and a subject-by-visit random effect that allows for extra-Poisson variation. This example is from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS documentation page](https://chjackson.github.io/openbugsdoc/Examples/Epil.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.epil`, which ships with the package.

## Model

For patient ``j = 1, \dots, 59`` and visit ``k = 1, \dots, 4``,

```math
\begin{aligned}
y_{jk} &\sim \text{Poisson}(\mu_{jk}) \\
\log \mu_{jk} &= a_0
  + \alpha_{\text{Base}} \left( \log(\text{Base}_j / 4) - \overline{\log(\text{Base}/4)} \right)
  + \alpha_{\text{Trt}} \left( \text{Trt}_j - \overline{\text{Trt}} \right)
  + \alpha_{\text{BT}} \left( \text{BT}_j - \overline{\text{BT}} \right) \\
  &\quad + \alpha_{\text{Age}} \left( \log(\text{Age}_j) - \overline{\log(\text{Age})} \right)
  + \alpha_{\text{V4}} \left( \text{V4}_k - \overline{\text{V4}} \right)
  + b1_j + b_{jk} \\
b1_j &\sim \text{Normal}(0, \sigma_{b1}^2), \qquad
b_{jk} \sim \text{Normal}(0, \sigma_b^2)
\end{aligned}
```

with vague normal priors on the coefficients and vague gamma priors on the random-effect precisions. The original BUGS program uses R-style dotted names such as `alpha.Base` and `tau.b`; in Julia these are written with the `var"..."` syntax, which lets a variable name contain a dot.

```@example epil
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.epil
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example epil
print(example.original_syntax_program)
```

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="epil" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data set is too large to display comfortably here, so we load it from the copy that ships with JuliaBUGS. It contains `N = 59` patients and `T = 4` visits, the `59 × 4` matrix `y` of seizure counts, the treatment indicator `Trt` (0 = placebo, 1 = active treatment), the baseline seizure count `Base`, each patient's `Age` in years, and `V4`, an indicator that equals 1 only at the fourth visit.

```@example epil
data = example.data
```

```@example epil
inits = example.inits
model = compile(example.model_def, data, inits)
```

We pass the example's published initial values to `compile` rather than compiling from the data alone. This is a log-linear Poisson model with vague priors, so values drawn at random from the priors can produce an invalid (non-positive or overflowing) rate; starting from sensible values keeps construction and sampling stable.

## Sampling

To draw posterior samples, we build the model with gradient support and run the NUTS sampler from AdvancedHMC:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data, inits; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.epil.inits` and can be applied with `initialize!(model, inits)`.

## Results

JuliaBUGS does not ship reference results for this example. For published estimates, see the [OpenBUGS documentation page](https://chjackson.github.io/openbugsdoc/Examples/Epil.html), which reports results alongside the approximate-likelihood fit of Breslow and Clayton (1993); a correctly converged chain's `summarystats` should agree with those values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="epil"></div>
```

See also: the [example gallery overview](../index.md) and the [getting started tutorial](../../getting_started.md).
