# Rats: Normal Hierarchical Model

This example is taken from section 6 of Gelfand et al. (1990) and concerns 30 young rats whose weights were measured weekly for five weeks. Each rat therefore contributes five weight measurements $Y_{ij}$, taken at ages $x_j = 8, 15, 22, 29, 36$ days. The question is how to describe the growth of the population as a whole while allowing each animal its own growth trajectory: a plot of the 30 growth curves suggests broadly linear growth with some evidence of downward curvature and clear rat-to-rat variation in both starting weight and growth rate.

The model is a random-effects linear growth curve — a normal hierarchical model in which each rat has its own intercept and slope, and these rat-level coefficients are in turn drawn from common population distributions. The ages are centred at their mean $\bar{x} = 22$ to reduce dependence between the intercepts and slopes. Interest focuses in particular on the population intercept at birth (age zero), $\alpha_0 = \alpha_c - \beta_c \bar{x}$. It is the first example in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Rats.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.rats`, which ships with the package.

## Model

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}\left(\alpha_i + \beta_i (x_j - \bar{x}),\ \tau_c\right) \\
\alpha_i &\sim \text{Normal}(\alpha_c, \tau_\alpha) \\
\beta_i &\sim \text{Normal}(\beta_c, \tau_\beta)
\end{aligned}
```

where $\tau$ denotes the precision (inverse variance) of a normal distribution, following the BUGS convention. The population parameters $\alpha_c$, $\tau_\alpha$, $\beta_c$, $\tau_\beta$, and $\tau_c$ are given independent "noninformative" priors.

```@example rats
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.rats
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example rats
print(example.original_syntax_program)
```

Names such as `var"tau.c"` are the R-style dotted variable names from the original BUGS program, written with Julia's `var"..."` syntax so they can be kept exactly as they appear in the classic example.

## Data

The data are supplied as a `NamedTuple`: the measurement ages `x`, their mean `xbar`, the number of rats `N`, the number of measurement occasions `T`, and the 30-by-5 matrix `Y` of weights.

```@example rats
data = example.data
```

```@example rats
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
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.rats.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter | Mean  | Std    |
|-----------|-------|--------|
| `alpha0`  | 106.6 | 3.66   |
| `beta.c`  | 6.186 | 0.1086 |
| `sigma`   | 6.093 | 0.4643 |

A correctly converged chain's `summarystats` should reproduce these values up to Monte Carlo error.

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
