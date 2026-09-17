# Schools: ranking schoolexamination results using multivariate hierarcical models

This example concerns the examination results of 1978 pupils taught at 38 different schools. For each pupil the data record an exam score `Y`, a London Reading Test score `LRT` taken at intake, a verbal reasoning band `VR`, and the pupil's `Gender`. Two further variables describe the school rather than the pupil: `School.gender` codes the intake as all girls, all boys or mixed, and `School.denom` the school's denomination. The categorical variables arrive already expanded into indicator columns with one level held back as the baseline, which is why `VR` and `School.gender` occupy two columns each and `School.denom` three. The practical question is how to rank the 38 schools on exam performance once differences in the ability of the pupils they admit have been accounted for, which is exactly the sort of comparison a raw league table gets wrong.

The model is a multivariate hierarchical regression. Each school gets its own intercept and its own slopes on `LRT` and on the first verbal-reasoning indicator, and those three school-level coefficients are drawn jointly from a trivariate normal distribution whose mean vector `gamma` and precision matrix `T` are themselves estimated: `gamma` is given a multivariate normal prior and `T` a Wishart prior with 3 degrees of freedom and scale matrix `R`. Modelling the three coefficients jointly rather than separately lets the data say how a school's baseline level and its sensitivity to intake ability are correlated. The remaining eight covariate effects are common to all schools and are given vague independent normal priors.

The second unusual feature is that the residual precision is not constant. Rather than a single `tau`, the model lets the log precision of a pupil's score depend linearly on that pupil's intake score, so that pupils entering with low reading scores can be more variable in outcome than those entering with high ones:

```math
\begin{aligned}
Y_p &\sim \text{Normal}(\mu_p,\ \tau_p) \\
\log \tau_p &= \theta + \phi \, \mathrm{LRT}_p \\
\alpha_j &\sim \text{MVNormal}(\gamma,\ T), \qquad j = 1, \ldots, 38
\end{aligned}
```

following the BUGS convention in which the second argument of a normal distribution is the precision, the inverse of the variance. The derived quantities `min.var` and `max.var` evaluate the implied residual variance at the lowest and highest `LRT` scores in the data, -34.6193 and 37.3807, which is the readable way to report how much the variance actually changes across the range. See [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Schools page](https://chjackson.github.io/openbugsdoc/Examples/Schools.html) for the original write-up.

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.schools`, which ships with the package.

## Model

```@example volume_2_schools
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.schools
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_schools
print(example.original_syntax_program)
```

## Data

```@example volume_2_schools
example.data
```

## Compiling the model

```@example volume_2_schools
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_2_schools
example.reference_results
```
