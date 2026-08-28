# Fun Shapes: Square minus Circle

This model is the [Circle](circle.md) model with a single digit changed, and it produces the hardest target in the Fun Shapes group. The two coordinates are again uniform on the square $[-1, 1]^2$ and the constraint expression is identical, `constraint = step(x * x + y * y - 1)`, but the Bernoulli node `O` is fixed to 1 rather than 0. That reverses which outcome the observation demands, so the density now survives exactly where the step function returns 1, that is where $x^2 + y^2 \ge 1$, the complement of the disc. What is left is the four corner pieces of the square, with a total area of $4 - \pi \approx 0.86$.

```math
\{(x, y) \in [-1, 1]^2 \; : \; x^2 + y^2 \ge 1\}
```

The difficulty is that the support is effectively disconnected. The four corners touch only at the isolated points $(\pm 1, 0)$ and $(0, \pm 1)$, which a chain will never visit, so any sampler that moves in local steps stays in the corner it was started in. The bundled initial values put it at $(0.99, 0.99)$, in the top right corner. A single chain can then look perfectly well behaved and still be wrong: the target is symmetric under reflection in either axis and under exchanging $x$ and $y$, while the chain reports one quadrant only. That makes this the standard demonstration in the set of why dispersed multiple chains matter, and of why a diagnostic computed within a single chain cannot see this kind of failure. The original write-up is on the [MultiBUGS Volume III examples page](https://www.multibugs.org/examples/latest/VolumeIII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.square_minus_circle`, which ships with the package.

## Model

```@example volume_3_square_minus_circle
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.square_minus_circle
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_square_minus_circle
print(example.original_syntax_program)
```

## Data

```@example volume_3_square_minus_circle
example.data
```

## Compiling the model

```@example volume_3_square_minus_circle
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

```@example volume_3_square_minus_circle
example.reference_results
```

