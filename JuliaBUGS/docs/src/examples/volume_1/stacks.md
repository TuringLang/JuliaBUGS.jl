# Stacks: Robust Regression

This example comes from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Stacks.html)). It analyses Brownlee's much-studied stack loss data: 21 days of operation of a plant that oxidises ammonia to nitric acid. The response `Y` is the "stack loss" — the amount of ammonia escaping up the stack — and the three covariates in `x` are air flow, cooling water inlet temperature, and acid concentration.

The model is a linear regression of stack loss on the standardised covariates. Because this data set is famous for containing outliers, the original BUGS example uses it to illustrate robust regression: the same linear predictor can be combined with normal, double-exponential, or Student-t(4) error distributions, and each observation gets an `outlier` indicator that flags standardised residuals larger than 2.5 in absolute value. The version shipped with JuliaBUGS uses normal errors; the alternative error distributions (and an exchangeable "ridge regression" prior on the coefficients) appear as comments in the model code, exactly as in the original.

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.stacks`, which ships with the package.

## Model

Writing ``z_{ij}`` for the standardised covariates, the (normal-errors) model is

```math
\begin{aligned}
\mu_i &= \beta_0 + \beta_1 z_{i1} + \beta_2 z_{i2} + \beta_3 z_{i3} \\
Y_i &\sim \text{Normal}(\mu_i, \tau) \qquad i = 1, \ldots, 21
\end{aligned}
```

where, following BUGS convention, ``\tau`` is a precision (``\sigma = 1/\sqrt{\tau}``). The intercept and coefficients get vague normal priors and ``\tau`` gets a vague gamma prior. The coefficients on the original (unstandardised) scale are recovered as `b` and `b0`.

```@example stacks
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.stacks
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example stacks
print(example.original_syntax_program)
```

## Data

The data are the 21 stack loss measurements `Y` and the 21 x 3 covariate matrix `x` (air flow, temperature, acid concentration), together with the dimensions `N` and `p`. Compiling the model definition with the data produces a runnable model.

```@example stacks
data = example.data
```

```@example stacks
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

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.stacks.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter     | Mean   | Std    |
|:------------- |:------ |:------ |
| `b0`          | -39.64 | 12.63  |
| `outlier[21]` | 0.3324 | 0.4711 |

A correctly converged chain's `summarystats` should reproduce these values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="stacks"></div>
```

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
