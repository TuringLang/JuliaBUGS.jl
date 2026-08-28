# Fun Shapes: Parallelogram

The other shapes in the Fun Shapes group are awkward because of where their boundaries run; this one is awkward because of which way it leans. The construction is the same as on the [Circle](circle.md) page, with no data and nothing to estimate, but here $x$ is uniform on $(0, 1)$ and $y$ is uniform on $(-1, 1)$, and two Bernoulli nodes trim the resulting rectangle down to a slanted band. `O1` is fixed to 1 and given probability `step(x + y)`, which forces $x + y \ge 0$; `O2` is fixed to 0 and given probability `1 - step(x + y - 1)`, which forces $x + y < 1$. The support is the parallelogram with corners $(0, 0)$, $(0, 1)$, $(1, 0)$ and $(1, -1)$, lying between the lines $x + y = 0$ and $x + y = 1$.

```math
\{(x, y) \; : \; 0 \le x \le 1, \; 0 \le x + y < 1\}
```

Being convex, with no hole to trap a chain, the band presents a difficulty of a different kind: correlation. Writing a point of the band as $y = u - x$ with $u$ uniform on $(0, 1)$ and independent of $x$ shows that $x$ stays uniform, that $y$ has a triangular density on $(-1, 1)$ peaked at zero, and that the two are correlated at $-1/\sqrt{2}$, about $-0.71$. A sampler that updates one coordinate at a time can therefore only take short steps across the narrow diagonal band and mixes slowly, which makes this a compact illustration of why axis-aligned updates struggle with a rotated support. The bundled initial values start at $(0.5, 0)$, in the middle of the band. The original write-up is on the [MultiBUGS Volume III examples page](https://www.multibugs.org/examples/latest/VolumeIII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.parallelogram`, which ships with the package.

## Model

```@example volume_3_parallelogram
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.parallelogram
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_parallelogram
print(example.original_syntax_program)
```

## Data

```@example volume_3_parallelogram
example.data
```

## Compiling the model

```@example volume_3_parallelogram
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

```@example volume_3_parallelogram
example.reference_results
```

