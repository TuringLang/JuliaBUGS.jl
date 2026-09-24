# Mice: Weibull Regression

This example analyses survival data from a photocarcinogenicity experiment, taken from Grieve (1987). Four treatment groups of 20 mice each were followed over time, and for each animal the survival time (in weeks) was recorded. Some animals were still alive when the study ended, so their survival times are *right-censored*: we only know that the animal lived at least as long as its recorded follow-up time, not exactly how long it would have survived.

The goal is to describe how survival varies across the four treatment groups. Survival times are modelled with a Weibull distribution whose shape parameter `r` is shared across all animals and whose scale depends on the animal's treatment group through a group-specific coefficient `beta`. This is a Weibull regression (accelerated-failure-time style) survival model with censored observations. From the group coefficients the model derives the median survival time in each group and a set of contrasts comparing the three active treatments against the first (control) group.

This is one of the classic examples from Volume 1 of the BUGS examples; see the [MultiBUGS Volume I collection](https://www.multibugs.org/examples/latest/VolumeI.html) and the matching [OpenBUGS Mice page](https://chjackson.github.io/openbugsdoc/Examples/Mice.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.mice`, which ships with the package.

## Model

Writing $r$ for the shared Weibull shape, $\beta_i$ for the coefficient of group $i$, and $\mu_i = \exp(\beta_i)$ for the corresponding Weibull scale parameter, the model is

```math
\begin{aligned}
t_{ij} &\sim \text{Weibull}(r, \mu_i) \quad \text{(right-censored at } t^{\text{cen}}_{ij}) \\
\mu_i &= \exp(\beta_i) \\
\beta_i &\sim \text{Normal}(0, 0.001) \\
\text{median}_i &= \big(\log 2 \cdot \exp(-\beta_i)\big)^{1/r} \\
r &\sim \text{Uniform}(0.1, 10)
\end{aligned}
```

where the Normal prior on each $\beta_i$ is written in BUGS' mean/precision parameterisation (precision $0.001$).

```@example mice
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.mice
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example mice
print(example.original_syntax_program)
```

The names `var"t.cen"`, `var"veh.control"`, `var"test.sub"`, and `var"pos.control"` are R-style dotted names carried over verbatim from the original BUGS program; Julia allows such non-standard identifiers through its `var"..."` syntax.

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="mice" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data hold the survival times and censoring information for the `M = 4` groups of `N = 20` mice each. In the `t` matrix, a `missing` entry marks an animal whose survival time was censored; the corresponding entry of `var"t.cen"` gives the time at which that animal was last known to be alive (a value of `0` means the animal's survival time was observed exactly).

```@example mice
data = example.data
```

```@example mice
model = compile(example.model_def, data)
```

## Sampling

With the model constructed, we attach an automatic-differentiation backend and draw posterior samples with the No-U-Turn sampler:

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

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.mice.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censored observations"
    Several survival times in this example are right-censored: the animal was still alive when the study ended, so its survival time is missing and known only to exceed the follow-up time `t.cen[i, j]`. The program says so with `C(t.cen[i, j], )` after `dweib`. A censored animal then contributes the Weibull probability of surviving beyond `t.cen[i, j]`, rather than a density at an observed time.

## Results

Unlike some of the other Volume 1 examples, this one does not ship with a tabulated reference posterior summary — `JuliaBUGS.BUGSExamples.VOLUME_1.mice.reference_results` is `nothing`, so there are no stored means and standard deviations to reproduce here. The published estimates for the shape parameter `r`, the group medians, and the treatment contrasts are reported on the [OpenBUGS Mice page](https://chjackson.github.io/openbugsdoc/Examples/Mice.html) (obtained there from a burn-in of 1000 updates followed by 10000 further updates). Once your chain has converged, the posterior means and standard deviations from `summarystats(chain)` should agree with those published values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="mice"></div>
```

See also: the [Example Gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
