# Stagnant: a changepoint problem and an illustration of how NOT to do MCMC!)

The data are 29 paired measurements of a response `Y` against a covariate `x`. The covariate runs from -1.39 up to 1.19 and the response falls steadily from 1.12 down to -0.65, but not at a constant rate: plotted, the points lie on two straight-line segments that meet somewhere in the middle. The question is where the two segments join and how the slope differs either side of that join, which makes this a changepoint regression.

The model puts a normal likelihood on `Y` with a common precision `tau`, and builds the mean as a single intercept `alpha` at the changepoint plus one of two slopes, selected by which side of the changepoint the observation falls on. The `step` function does the selecting, returning 0 below the changepoint and 1 at or above it, so that `J[i]` indexes into `beta`:

```math
Y_i \sim \text{Normal}(\mu_i,\ \tau), \qquad \mu_i = \alpha + \beta_{J_i}\,(x_i - x_{\text{change}}), \qquad J_i = 1 + \text{step}(x_i - x_{\text{change}})
```

Because both segments are written as deviations from the same `alpha` at the same `x.change`, the fitted line is continuous by construction and only its slope is allowed to break. The changepoint itself is an unknown parameter with a uniform prior between the 5th and 26th ordered covariate values, `x[5] = -0.94` and `x[26] = 0.85`; `alpha`, the two slopes, and `tau` get the usual vague priors, with the normal parameterised by precision rather than variance in the BUGS convention.

The title of this example is not a joke, and it is worth being precise about where the difficulty actually lies. It is not that the density jumps: because each segment is measured from the changepoint, the two branches agree exactly where they meet, so moving `x.change` past an observed $x_i$ changes nothing abruptly. What it does change is the slope of the log density, which acquires a kink at each of the 29 covariate values, leaving a surface that is continuous but only piecewise smooth. The real problem is the parameterisation. `alpha` is the expected response *at* the changepoint, so it is strongly correlated with `x.change`, and each slope is informed only by the observations currently on its own side of the split, which the changepoint itself decides. A componentwise sampler therefore moves the changepoint in very small steps, and a chain can sit in one region for a long time looking perfectly settled.

The version originally distributed made this far worse by treating the changepoint as a discrete index `k` over the observed covariate values, updated one position at a time; the shipped initial values still carry a value for `k`, a fossil of that formulation, though no such node exists in the model above. The continuous `x.change` coded here is the recommended repair rather than the cautionary version. Two sets of initial values ship with the example, `example.inits` starting the intercept at 0.2 and `example.inits_alternative` at 0.6, so the sensitivity to starting values can be examined. Treat any single chain here with suspicion, run several from dispersed starts, and compare them. See [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Stagnant page](https://chjackson.github.io/openbugsdoc/Examples/Stagnant.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.stagnant`, which ships with the package.

## Model

```@example volume_2_stagnant
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.stagnant
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_stagnant
print(example.original_syntax_program)
```

## Data

```@example volume_2_stagnant
example.data
```

## Compiling the model

```@example volume_2_stagnant
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

## Sampling

This block is not executed when the documentation is built, so that the
build stays fast; run it locally to reproduce the numbers below.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, MCMCChains, LogDensityProblems

model = JuliaBUGS.compile(example.model_def, example.data)
model = JuliaBUGS.initialize!(model, example.inits)
ad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
chain = AbstractMCMC.sample(
    ad_model, NUTS(0.8), n_samples;
    chain_type=Chains, n_adapts=n_adapts, discard_initial=n_adapts,
)
summarystats(chain)
```

## Reference results

The posterior summaries published with the original example. A converged
chain should reproduce these up to Monte Carlo error.

```@example volume_2_stagnant
example.reference_results
```

