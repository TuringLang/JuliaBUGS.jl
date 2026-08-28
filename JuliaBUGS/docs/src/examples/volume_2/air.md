# Air: Berkson measurement error

Do children who breathe more nitrogen dioxide (NO2) at home report more respiratory illness? Whittemore and Keller (1988) put the question to records on 103 children, and Stephens and Dellaportas (1992) later revisited the same records by Bayesian methods. The children are divided into three groups according to the NO2 concentration measured in the child's bedroom, with `n` = 48, 34 and 21 children in the three groups and `y` = 21, 20 and 15 of them reporting illness. The covariate `Z` records the nominal concentration attached to each group, 10, 30 and 50, the midpoints of the three categories. The question is how the probability of respiratory illness varies with exposure.

The complication is that the bedroom reading is only a surrogate for the exposure that matters, the true average NO2 level `X` experienced by a child in that group. Here the calibration linking the two is treated as known, so `X[j]` is drawn from a normal distribution centred on $\alpha + \beta Z_j$ with $\alpha = 4.48$, $\beta = 0.76$ and precision $\tau = 0.01234$, corresponding to a residual variance of about 81. Because the unobserved true covariate is written as a function of the observed one rather than the other way round, this is a Berkson measurement-error model: the error is independent of the recorded `Z` and correlated with the true exposure.

```math
\begin{aligned}
y_j &\sim \text{Binomial}(p_j,\ n_j), \qquad j = 1, 2, 3 \\
\text{logit}(p_j) &= \theta_1 + \theta_2 X_j \\
X_j &\sim \text{Normal}(\alpha + \beta Z_j,\ \tau)
\end{aligned}
```

As always in BUGS, the second argument of the normal is a precision rather than a variance. Only the logistic-regression coefficients $\theta_1$ and $\theta_2$, given vague independent normal priors with precision 0.001, and the three latent exposures $X_j$ are estimated; $\alpha$, $\beta$ and $\tau$ are supplied as data. With three binomial observations and three latent covariates there is very little information in the data about the slope, so the posterior for $\theta_2$ is correspondingly wide. This is one of the examples in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Air.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.air`, which ships with the package.

## Model

```@example volume_2_air
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.air
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_air
print(example.original_syntax_program)
```

## Data

```@example volume_2_air
example.data
```

## Compiling the model

```@example volume_2_air
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

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

```@example volume_2_air
example.reference_results
```

