# Fun Shapes: Ring

An annulus keeps the hole of the [Hollow Square](hollow_square.md) but trades its straight edges for a smooth curve, and makes the obstruction radially symmetric so that any bias it induces is easy to spot in the output. As with the rest of the Fun Shapes group, described on the [Circle](circle.md) page, there is no data and nothing to estimate. Both coordinates are uniform on the square $[-1, 1]^2$, and two Bernoulli nodes bound the radius from either side. `O1` is fixed to 0 with `constraint1 = step(x * x + y * y - 1)`, which requires $x^2 + y^2 < 1$, and `O2` is fixed to 1 with `constraint2 = step(x * x + y * y - 0.25)`, which requires $x^2 + y^2 \ge 0.25$. What is left is the ring between radius $0.5$ and radius $1$.

```math
\{(x, y) \; : \; 0.25 \le x^2 + y^2 < 1\}
```

The ring is connected, so every part of it is in principle reachable, but it is not simply connected and the route from one side to the other has to go around the central hole rather than through it. Component-wise updating feels the hole directly: for $|x| < 0.5$ the conditional distribution of $y$ splits into two separate intervals, one above the hole and one below, and a single-site update cannot cross from one to the other in a single move. Because the target is radially symmetric, any imbalance between opposite parts of the ring in the output is a sign that the chain has been stuck. The bundled initial values start at $(0.6, 0.6)$, a radius of about $0.85$, inside the ring. The original write-up is on the [MultiBUGS Volume III examples page](https://www.multibugs.org/examples/latest/VolumeIII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.ring`, which ships with the package.

## Model

```@example volume_3_ring
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.ring
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_ring
print(example.original_syntax_program)
```

## Data

```@example volume_3_ring
example.data
```

## Compiling the model

```@example volume_3_ring
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

```@example volume_3_ring
example.reference_results
```

