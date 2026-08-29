# Hepatitis: a normal hierarchical model with measurement error (with measurement error)

This is the measurement-error version of the [Hepatitis](hepatitis.md) example, and it uses exactly the same data: the same 106 vaccinated children, their log anti-Hb titres in the 106-by-3 matrix `Y` (76 children measured three times, 30 twice, so 288 observed titres), the matching log measurement times in `t`, and the log titre at vaccination in the baseline covariate `y0`.

The regression structure is unchanged: each child has its own intercept $\alpha_i$ and slope $\beta_i$ against log time centred at 6.5, drawn from common population normals, and a single population coefficient $\gamma$ carries the effect of the baseline. What the measurement-error version adds is the recognition that `y0` is a titre reading like any other, and therefore not the child's true baseline. A latent true baseline $\mu_{0i}$ is introduced for each child, the observed `y0[i]` is treated as a noisy reading of it with the same precision $\tau$ that governs the repeat titres, and the regression uses $\mu_{0i}$ in place of `y0[i]`. The latent baselines are themselves drawn from a population normal with mean $\theta$ and precision $\psi$, both estimated.

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}\left(\alpha_i + \beta_i (t_{ij} - 6.5) + \gamma\,(\mu_{0i} - \bar{y}_0),\ \tau\right) \\
y_{0i} &\sim \text{Normal}(\mu_{0i}, \tau), \qquad \mu_{0i} \sim \text{Normal}(\theta, \psi)
\end{aligned}
```

As elsewhere in BUGS the second argument of `dnorm` is a precision rather than a variance. The centring term $\bar{y}_0$ is still the mean of the observed baselines, so only the covariate value itself becomes latent. The consequence is the classic one: regressing on a covariate measured with error attenuates its coefficient, and correcting for the error pulls $\gamma$ away from zero. The bundled reference summaries make this visible, with $\gamma$ near 0.67 in the basic model and near 1.08 here, while the growth-curve parameters $\alpha_0$ and $\beta_0$ barely move. This example is part of Volume 3 of the classic BUGS examples; see the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeIII.html) and the [OpenBUGS Hepatitis page](https://chjackson.github.io/openbugsdoc/Examples/Hepatitis.html), where this model appears under "With measurement error".

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hepatitis_me`, which ships with the package.

## Model

```@example volume_3_hepatitis_me
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hepatitis_me
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hepatitis_me
print(example.original_syntax_program)
```

## Data

```@example volume_3_hepatitis_me
example.data
```

## Compiling the model

```@example volume_3_hepatitis_me
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_3_hepatitis_me
example.reference_results
```
