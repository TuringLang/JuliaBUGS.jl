# Endo: conditional inference in case-control studies

This example analyses a matched case-control study of endometrial cancer, from the data of Breslow and Day (1980). There are `I = 183` strata, each one a case matched with a single control, and the exposure of interest, estrogen use, is binary. The data are supplied in collapsed form as three counts: 43 pairs in which the case was exposed and the control was not, 7 in which the control was exposed and the case was not, and 12 in which both were exposed. The remaining 121 pairs, in which neither member was exposed, are implied by the total. The model itself expands these counts back into the full 183-by-2 exposure array `est` and the response array `Y` using deterministic loops, so the only actual data the program needs are the four numbers.

The estimand is a single log odds ratio `beta` for the exposure, and the point of the example is how to estimate it without also estimating a nuisance intercept for every one of the 183 strata. The trick is conditional inference: given that exactly one member of each pair is a case, the probability that the case is the exposed member depends on `beta` alone, and the stratum-specific baseline risk cancels out. In BUGS this conditional likelihood is written as a one-trial multinomial over the two members of the pair:

```math
Y_{i,1:2} \sim \text{Multinomial}(p_{i,1:2},\ 1), \qquad p_{ij} = \frac{\exp(\beta\, \mathrm{est}_{ij})}{\exp(\beta\, \mathrm{est}_{i1}) + \exp(\beta\, \mathrm{est}_{i2})}
```

One consequence falls straight out of that expression: when both members of a pair share the same exposure the two probabilities are equal at one half whatever `beta` is, so only the 50 discordant pairs carry any information about the odds ratio. `beta` is given a vague normal prior with precision 1.0E-6, precision rather than variance being the BUGS convention.

Two alternative codings of the same problem are kept in the source as comments: a plain logistic regression on the within-pair exposure difference, and a set of Poisson regressions with an explicit nuisance intercept per stratum. See [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Endo page](https://chjackson.github.io/openbugsdoc/Examples/Endo.html) for the background to the study and the published comparison of the three approaches.

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.endo`, which ships with the package.

## Model

```@example volume_2_endo
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.endo
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_endo
print(example.original_syntax_program)
```

## Data

```@example volume_2_endo
example.data
```

## Compiling the model

```@example volume_2_endo
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_2_endo
example.reference_results
```
