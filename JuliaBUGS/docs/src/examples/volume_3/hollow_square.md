# Fun Shapes: Hollow Square

A square frame is the first support in the Fun Shapes group with a hole in it, and so the first in which a single-site sampler can get genuinely stuck. The setting is the one the [Circle](circle.md) page describes: no data, nothing to estimate, and a flat density on a region that a constraint node carves out. Both coordinates are uniform on the square $[-1, 1]^2$, and a single Bernoulli node punches out the middle: `constraint = step(0.5 - abs(x)) * step(0.50 - abs(y))` equals 1 exactly when $|x| \le 0.5$ and $|y| \le 0.5$, and fixing `O` to 0 gives that combination probability zero. What survives is the outer square with the central square of half-width 0.5 removed, an area of $4 - 1 = 3$.

```math
\{(x, y) \in [-1, 1]^2 \; : \; \max(|x|, |y|) > 0.5\}
```

The frame is connected all the way round, and its boundary is made entirely of straight edges and corners rather than a smooth curve. That combination is what makes it a useful test. A sampler that moves one coordinate at a time sees a conditional distribution for $y$ that is a single interval when $|x| > 0.5$ but a pair of disjoint intervals when $|x| \le 0.5$, and getting from one arm of the frame to the opposite arm means travelling around a corner instead of straight across. The marginal of $x$ gives a quick check on the output: it is piecewise constant, and exactly twice as high for $|x| > 0.5$ as for $|x| < 0.5$. The bundled initial values start at $(0.75, 0.75)$, in one corner of the frame. The original write-up is on the [MultiBUGS Volume III examples page](https://www.multibugs.org/examples/latest/VolumeIII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hollow_square`, which ships with the package.

## Model

```@example volume_3_hollow_square
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hollow_square
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hollow_square
print(example.original_syntax_program)
```

## Data

```@example volume_3_hollow_square
example.data
```

## Compiling the model

```@example volume_3_hollow_square
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

```@example volume_3_hollow_square
example.reference_results
```

