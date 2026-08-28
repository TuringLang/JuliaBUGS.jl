# Alligators: multinomial - logistic regression

The data are stomach contents for 219 alligators (Agresti's published table quotes 221; the array shipped with this example sums to 219), cross-classified three ways: by which of 4 lakes the animal came from, by which of 2 size classes it fell into, and by which of 5 food categories its primary stomach content belonged to. The counts arrive as a 4-by-2-by-5 array `X`, so each lake-and-size cell holds between 16 and 41 animals distributed over the five food types. The question is whether the food an alligator eats depends on where it lives and how big it is, and if so, how those two factors combine.

Statistically this is a multinomial logistic regression: within each lake-size cell the five counts are a multinomial draw, and the log odds of each food type relative to a baseline food are modelled additively as a lake effect plus a size effect. The model fits it in the equivalent Poisson form instead, which is the standard multinomial-Poisson transformation:

```math
X_{ijk} \sim \text{Poisson}(\mu_{ijk}), \qquad \log \mu_{ijk} = \lambda_{ij} + \alpha_k + \beta_{ik} + \gamma_{jk}
```

Here $\lambda_{ij}$ is a free parameter for each lake-size cell whose only job is to absorb that cell's total, so that the remaining structure reproduces the multinomial likelihood exactly. It is given a `dflat()` improper prior for that reason. The direct multinomial version is present in the source as commented-out code. Identifiability is imposed by corner-point contrasts, with $\alpha_1$, the whole first row of $\beta$, the whole first row of $\gamma$, and the first column of each of $\beta$ and $\gamma$ all fixed at zero; the derived quantities `b` and `g` recentre those contrasts to sum to zero so that they can be compared with Agresti's published analysis of the same table.

The `dflat()` prior is what currently prevents JuliaBUGS from compiling this model, as noted below, so the model definition and data on this page are for reference rather than for running. For the original analysis see [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Alligators page](https://chjackson.github.io/openbugsdoc/Examples/Aligators.html).

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

