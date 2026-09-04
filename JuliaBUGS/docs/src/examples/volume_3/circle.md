# Fun Shapes: Circle

The Fun Shapes group in Volume 3 is a set of toy models with no data and nothing to estimate. Each one puts a distribution on two coordinates that is flat over some geometric region and zero outside it, so the interest is entirely in the shape of the support and in how a sampler copes with it. Here the region is the unit disc. Both coordinates are given a uniform prior on the square $[-1, 1]^2$, and a single Bernoulli node switches the density off outside the circle: `constraint = step(x * x + y * y - 1)` is 1 whenever $x^2 + y^2 \ge 1$, and the node `O`, fixed at 0, has probability `1 - constraint`, so the density vanishes unless $x^2 + y^2 < 1$. This is the BUGS zeros trick used as a hard constraint rather than as a way of writing an unusual likelihood.

```math
\{(x, y) \in [-1, 1]^2 \; : \; x^2 + y^2 < 1\}
```

The disc is convex and connected, which makes this the mildest member of the set, but it already has the feature the group exists to expose: the log density is constant on the interior and undefined outside it, so there is no gradient anywhere to steer a proposal away from the boundary, and a move is either accepted as it stands or rejected outright. The output is easy to check by eye, since the draws should fill the disc evenly and the marginal density of $x$ should be proportional to the chord length $\sqrt{1 - x^2}$. The bundled initial values start the chain at the centre, $(0, 0)$. The original write-up is on the [MultiBUGS Volume III examples page](https://www.multibugs.org/examples/latest/VolumeIII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.circle`, which ships with the package.

## Model

```@example volume_3_circle
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.circle
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_circle
print(example.original_syntax_program)
```

## Compiling the model

```@example volume_3_circle
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.
