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

## Compiling the model

```@example volume_3_square_minus_circle
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.
