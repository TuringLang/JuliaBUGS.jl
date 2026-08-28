# Air: Berkson measurement error

<!-- PROSE: replace this line with a description of the model and its data. -->
This example is part of Volume 2 of the classic BUGS examples; the original write-up is on the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.air`, which ships with the package.

## Model

```@example volume_2_air
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.air
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_air
print(example.original_syntax_program)
```

## Data

```@example volume_2_air
example.data
```

## Compiling the model

```@example volume_2_air
model = JuliaBUGS.compile(example.model_def, example.data)
```

Initial values for the sampler are bundled too, as `example.inits` (a second set is available as `example.inits_alternative`).

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

```@example volume_2_air
example.reference_results
```

