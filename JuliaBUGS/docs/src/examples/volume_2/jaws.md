# Jaws: repeated measures analysis of variance

Elston and Grizzle (1962) tracked the ramus bone, part of the jaw, in 20 boys, recording its height four times at six-monthly intervals. The readings fall at $\text{age}_j = 8, 8.5, 9, 9.5$ years, so the data matrix `Y` is 20 by 4. What is wanted from them is the growth curve of the bone in the population, not a curve for any individual boy.

The four readings on a boy are repeated measurements of the same bone and are clearly not independent, so they are modelled jointly: each row of `Y` is drawn from a multivariate normal with a common mean vector $\mu$ and a common 4-by-4 precision matrix `Omega`, left entirely unstructured so that the correlations between occasions are estimated from the data rather than assumed. The mean follows a linear growth curve in age, $\mu_j = \beta_0 + \beta_1 \text{age}_j$. The original write-up fits a constant, a linear, and a quadratic curve in turn; the linear one is what is coded here.

```math
\begin{aligned}
Y_i &\sim \text{MVNormal}(\mu,\ \Omega), \qquad i = 1, \ldots, 20 \\
\mu_j &= \beta_0 + \beta_1\, \text{age}_j \\
\Omega &\sim \text{Wishart}(R,\ 4)
\end{aligned}
```

As with the univariate normal, BUGS parameterises the multivariate normal by its precision matrix $\Omega$ rather than its covariance; the model records the covariance separately as `Sigma`, the inverse of $\Omega$. The Wishart prior is made as vague as it can be by taking the degrees of freedom to be 4, the rank of the matrix, and by setting the scale matrix `R` to the 4-by-4 identity, which states only the rough scale on which the four measurements are expected to covary. The regression coefficients $\beta_0$ and $\beta_1$ get independent normal priors with precision 0.001. This is one of the examples in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Jaws.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.jaws`, which ships with the package.

## Model

```@example volume_2_jaws
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.jaws
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_jaws
print(example.original_syntax_program)
```

## Data

```@example volume_2_jaws
example.data
```

## Compiling the model

```@example volume_2_jaws
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_2_jaws
example.reference_results
```
