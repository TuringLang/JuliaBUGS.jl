# Equiv: Bioequivalence in a Cross-Over Trial

This example comes from Volume 1 of the classic [BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Equiv.html)). The data, originally from Gelfand et al. (1990), come from a two-treatment, two-period cross-over trial designed to compare two formulations of a drug, tablet A and tablet B. Ten subjects each receive both treatments, one in each of two periods, and a continuous response is measured on each occasion. The `group` variable records which order a subject was given the two treatments in, so that the treatment effect can be separated from a possible period effect.

The scientific question is one of *bioequivalence*: are the two formulations close enough to be considered interchangeable? The model estimates the treatment effect on the log scale, `phi`, and reports `theta = exp(phi)`, the ratio of the two treatment effects. By the usual regulatory convention, the two tablets are declared bioequivalent when `theta` lies between 0.8 and 1.2. This is a linear mixed (normal hierarchical) model with a subject-specific random effect `delta[i]` capturing between-subject variation.

## Model

Writing `\tau_1` and `\tau_2` for the two precisions (BUGS parameterises the normal by its precision, not its variance):

```math
\begin{aligned}
Y_{ik} &\sim \text{Normal}(m_{ik},\ \tau_1) \\
m_{ik} &= \mu + \tfrac{1}{2}\,\text{sign}[T_{ik}]\,\phi + \tfrac{1}{2}\,\text{sign}[k]\,\pi + \delta_i \\
\delta_i &\sim \text{Normal}(0,\ \tau_2) \\
\theta &= e^{\phi}
\end{aligned}
```

Here `mu` is the overall mean, `phi` is the treatment effect, `pi` is the period effect, and `equiv` is an indicator that equals 1 exactly when `theta` falls in the bioequivalence range (0.8, 1.2); its posterior mean is the posterior probability of bioequivalence.

```@example equiv
using JuliaBUGS

equiv = @bugs begin
    for k in 1:P
        for i in 1:N
            Y[i, k] ~ dnorm(m[i, k], tau1)
            m[i, k] = mu + (sign[T[i, k]] * phi) / 2 + (sign[k] * pi) / 2 + delta[i]
            T[i, k] = group[i] * (k - 1.5) + 1.5
        end
    end
    for i in 1:N
        delta[i] ~ dnorm(0.0, tau2)
    end
    tau1 ~ dgamma(0.001, 0.001)
    sigma1 = 1 / sqrt(tau1)
    tau2 ~ dgamma(0.001, 0.001)
    sigma2 = 1 / sqrt(tau2)
    mu ~ dnorm(0.0, 1.0e-6)
    phi ~ dnorm(0.0, 1.0e-6)
    pi ~ dnorm(0.0, 1.0e-6)
    theta = exp(phi)
    equiv = _step(theta - 0.8) - _step(theta - 1.2)
end
```

## Data

The data record the `N = 10` subjects and `P = 2` periods, the response matrix `Y`, the treatment-order indicator `group`, and the sign vector `sign` used to flip the treatment and period contributions. We supply everything as a `NamedTuple` and construct the model by calling the model definition with it:

```@example equiv
data = (
    N = 10,
    P = 2,
    group = [1, 1, -1, -1, -1, 1, 1, 1, -1, -1],
    Y = [1.4 1.65
         1.64 1.57
         1.44 1.58
         1.36 1.68
         1.65 1.69
         1.08 1.31
         1.09 1.43
         1.25 1.44
         1.25 1.39
         1.3 1.52],
    sign = [1, -1]
)

model = equiv(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples` — each entry bundles the model definition, the data, a set of initial values, and reference results.

## Sampling

To draw posterior samples, build the model with gradient support and run the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = equiv(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.equiv.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter | Mean | Std |
|-----------|------|-----|
| equiv | 0.998 | 0.04468 |
| mu | 1.436 | 0.05751 |
| phi | -0.008613 | 0.05187 |
| sigma1 | 0.1102 | 0.03268 |

A correctly converged chain's `summarystats` output should match these values up to Monte Carlo error.

See also: the [gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
