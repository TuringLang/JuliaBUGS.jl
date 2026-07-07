# Seeds: Random Effect Logistic Regression

This is the classic *Seeds* example from [Volume 1 of the BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html)). The data come from a seed germination experiment laid out as a 2×2 factorial design across 21 plates. For each plate we record the number of seeds that germinated, `r[i]`, out of the total number of seeds sown, `n[i]`. Two experimental factors are crossed: the seed type (`x1`) and the type of root extract used (`x2`).

The scientific question is how seed type, root extract, and their interaction affect the probability of germination, while acknowledging that plates differ from one another for reasons the covariates do not capture. To handle this extra plate-to-plate variability (over-dispersion relative to a plain binomial model), the model is a **random-effects logistic regression**: each plate gets its own random intercept `b[i]`, drawn from a common normal distribution whose precision `tau` is estimated from the data.

## Model

Let $p_i$ be the germination probability on plate $i$. The model is

```math
\begin{aligned}
b_i &\sim \text{Normal}(0, \tau) \\
\text{logit}(p_i) &= \alpha_0 + \alpha_1 x_{1i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_i \\
r_i &\sim \text{Binomial}(n_i, p_i)
\end{aligned}
```

with vague priors on the regression coefficients and a vague gamma prior on the random-effect precision `tau`. The derived quantity `sigma = 1 / sqrt(tau)` is the standard deviation of the plate random effects.

Here is the model written with the `@bugs` macro. Because Julia treats `f(x) = ...` as a function definition, the BUGS link-function form `logit(p[i]) <- ...` is written by applying the inverse link (`logistic`) on the right-hand side.

```@example seeds
using JuliaBUGS

seeds = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] +
                        b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

## Data

The data are supplied as a `NamedTuple`. `r` and `n` are the germinated and total seed counts on each of the `N = 21` plates, while `x1` and `x2` are the (0/1) indicators for seed type and root extract.

```@example seeds
data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21
)

model = seeds(data)
```

All of the classic examples ship with the package under `JuliaBUGS.BUGSExamples`, bundling the model definition, data, initial values, and published reference results (this one is `JuliaBUGS.BUGSExamples.VOLUME_1.seeds`).

## Sampling

To draw posterior samples, construct the model with gradient support and run the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = seeds(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.seeds.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter | Mean | Std |
| --- | --- | --- |
| alpha0 | -0.5499 | 0.1965 |
| alpha1 | 0.08902 | 0.3124 |
| alpha12 | -0.841 | 0.4372 |
| alpha2 | 1.356 | 0.2772 |
| sigma | 0.2922 | 0.1467 |

A correctly converged chain's `summarystats` output should match these values up to Monte Carlo error.

See also: [gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
