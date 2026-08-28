# Alligators: multinomial - logistic regression

<!-- PROSE: replace this line with a description of the model and its data. -->
This example is part of Volume 2 of the classic BUGS examples; the original write-up is on the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeII.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.alligators`, which ships with the package.

## Model

```@example volume_2_alligators
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.alligators
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_alligators
print(example.original_syntax_program)
```

## Data

```@example volume_2_alligators
example.data
```

## Compiling the model

!!! warning "Not yet supported"
    JuliaBUGS cannot compile this model yet:
    `MethodError: no method matching iterate(::JuliaBUGS.BUGSPrimitives.Flat)`.
    The model definition and data above are correct and ship with the
    package; only the compile step below is blocked. The block is shown
    but not executed.

```julia
model = JuliaBUGS.compile(example.model_def, example.data)
```

