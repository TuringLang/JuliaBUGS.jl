# Birats: a bivariate normal hierarchical model

This example returns to the [Rats](../rats.md) data, the 30 young rats whose weights were measured on five occasions at ages $x_j = 8, 15, 22, 29, 36$ days, and refits it with a multivariate population distribution for the growth-curve coefficients. In the univariate version each rat's intercept and slope are drawn from two separate normal distributions, which forces them to be independent a priori. Here the pair is drawn jointly from a bivariate normal, so the model can express a correlation between them: positive correlation would mean that rats which start out heavy also tend to gain weight faster. This is the model Gelfand et al. (1990) adopted for these data.

Each rat $i$ has a coefficient vector `beta[i, 1:2]` drawn from a bivariate normal with population mean `mu.beta` and population precision matrix `R`, and its five weights are normal about $\beta_{i1} + \beta_{i2} x_j$ with a common measurement precision `tauC`. The ages are not centred in this version, so $\beta_{i1}$ is the rat's intercept at age zero and `mu.beta[1]` is the population intercept at birth directly, the quantity that the Rats example has to construct as `alpha0`.

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}(\beta_{i1} + \beta_{i2} x_j,\ \tau_c) \\
\beta_i &\sim \text{MVNormal}(\mu_\beta,\ R) \\
\mu_\beta &\sim \text{MVNormal}(\text{mean},\ \text{prec}) \\
R &\sim \text{Wishart}(\Omega,\ 2)
\end{aligned}
```

Following the BUGS convention, the second argument of every normal here is a precision rather than a variance or a covariance matrix. The population mean gets a vague bivariate normal prior with mean zero and precision $10^{-6} I$, and the population precision matrix `R` a Wishart prior with 2 degrees of freedom, the smallest value its rank allows, and scale matrix $\Omega = \text{diag}(200, 0.2)$, whose entries say only how widely intercepts and slopes are expected to range relative to each other. The measurement precision gets the usual vague $\text{Gamma}(0.001, 0.001)$, with `sigma` recording the implied standard deviation. Note that the names in this program differ from those in the original write-up's algebra: the code's `R` is the population precision matrix, and `Omega` is the Wishart scale matrix. This is one of the examples in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/BiRats.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.birats`, which ships with the package.

## Model

```@example volume_2_birats
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.birats
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_birats
print(example.original_syntax_program)
```

## Data

```@example volume_2_birats
example.data
```

## Compiling the model

```@example volume_2_birats
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

```@example volume_2_birats
example.reference_results
```

