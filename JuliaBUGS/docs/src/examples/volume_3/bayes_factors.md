# Bayes Factors: Using pseudo priors with Carlin and Chib method

This example, called Pines in the original BUGS distribution, demonstrates the Carlin and Chib method for computing a Bayes factor between two non-nested models. The data are 42 observations of a response `Y` together with two competing single-covariate predictors `x` and `z`. Both explain the response well on their own, with correlations against `Y` of about 0.93 and 0.95, and they are also strongly correlated with each other, at about 0.96. Choosing between two regressions this similar is exactly the situation in which a Bayes factor is wanted and in which ordinary posterior summaries from either model separately say nothing about the comparison.

The trick is to make the model index itself a parameter. All three variables are standardised inside the program, a categorical node `j` picks model 1 or model 2, and the likelihood is written once as $Y^s_i \sim \text{Normal}(\mu_{j,i}, \tau_j)$ with $\mu_{1,i} = \alpha + \beta x^s_i$ and $\mu_{2,i} = \gamma + \delta z^s_i$. Both models' parameters exist at every iteration, but which prior they see depends on `j`: the selected model's parameters are given their genuine vague estimation priors and are updated by the data, while the unselected model's parameters are drawn from pseudo-priors. Those pseudo-priors are deliberately tight approximations to what the parameters look like under their own model, for instance a precision of 256 on $\alpha$ and $\beta$ when model 2 is active and 400 on $\gamma$ and $\delta$ when model 1 is active. They do not enter the marginal posterior for `j`, but they keep the dormant parameters in a plausible region so that the chain can switch models at a workable rate instead of getting stuck.

The prior over models is deliberately lopsided, `p[1] = 0.9995` against `p[2] = 0.0005`. The data favour the second model strongly enough that a uniform prior would leave model 1 essentially unvisited, so the prior is tilted the other way to keep both states in play; the tilt is then divided back out. The monitored quantity is `pM2 = step(j - 1.5)`, whose posterior mean estimates $P(M_2 \mid \text{data})$, and the Bayes factor is the posterior odds divided by the prior odds:

```math
B_{21} = \frac{P(M_2 \mid \text{data})}{1 - P(M_2 \mid \text{data})} \times \frac{p_1}{p_2}
```

With the bundled reference value of `pM2` this comes out in the thousands, decisively in favour of the second model. Note that `j` is a discrete parameter, so this example needs a sampler that can update discrete nodes. This example is part of Volume 3 of the classic BUGS examples; see the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeIII.html) and the [OpenBUGS Pines page](https://chjackson.github.io/openbugsdoc/Examples/Pines.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.bayes_factors`, which ships with the package.

## Model

```@example volume_3_bayes_factors
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.bayes_factors
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_bayes_factors
print(example.original_syntax_program)
```

## Data

```@example volume_3_bayes_factors
example.data
```

## Compiling the model

```@example volume_3_bayes_factors
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_3_bayes_factors
example.reference_results
```
