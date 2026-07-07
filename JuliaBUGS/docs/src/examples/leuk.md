# Leuk: Cox Regression

This example is the classic leukemia survival dataset, in which the remission times of 42 patients are compared between two treatment groups. In the data each patient carries a treatment covariate `Z` coded as $\pm 0.5$ (21 patients in each group), an observed time `obs.t`, and a failure indicator `fail` that records whether the observed time is a true failure or a right-censored follow-up time. The goal is to estimate the effect of treatment on the hazard of relapse and to recover the survival curve in each group.

The model is a Cox proportional-hazards regression in which the integrated baseline hazard is estimated non-parametrically, following the counting-process formulation of Clayton (1994) using the notation of Andersen and Gill (1982). Rather than fitting a censored survival likelihood directly, the increments of each patient's counting process are treated as independent Poisson variables whose means depend on a risk-set indicator, the treatment effect $\beta$, and the jump $d\Lambda_0$ in the baseline hazard over each time interval; the hazard increments are given a conjugate gamma-process prior. This reformulation looks somewhat indirect, but it lays the groundwork for extensions to frailty models, time-dependent covariates, and smoothed hazards. It is one of the examples in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Leuk.html).

## Model

```math
\begin{aligned}
dN_i(t_j) &\sim \text{Poisson}\left(I_i(t_j)\right) \\
I_i(t_j) &= Y_i(t_j)\, \exp(\beta z_i)\, d\Lambda_0(t_j) \\
d\Lambda_0(t_j) &\sim \text{Gamma}\left(c\, d\Lambda_0^*(t_j),\ c\right) \\
\beta &\sim \text{Normal}(0,\ 10^{-6})
\end{aligned}
```

Here $Y_i(t_j)$ is the risk-set indicator (1 if patient $i$ is still under observation at time $t_j$), $dN_i(t_j)$ counts a failure of patient $i$ in the interval starting at $t_j$, and $d\Lambda_0^*$ is a prior guess at the hazard with $c$ controlling the strength of that guess.

```@example leuk
using JuliaBUGS

leuk = @bugs begin
    # Set up data
    for i in 1:N
        for j in 1:T
            # risk set = 1 if obs.t >= t
            Y[i, j] = step(var"obs.t"[i] - t[j] + eps)
            # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
            # i.e. if t[j] <= obs.t < t[j+1]
            dN[i, j] = Y[i, j] * step(t[j + 1] - var"obs.t"[i] - eps) * fail[i]
        end
    end

    # Model
    for j in 1:T
        for i in 1:N
            dN[i, j] ~ dpois(Idt[i, j]) # Likelihood
            Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]    # Intensity
        end
        dL0[j] ~ dgamma(mu[j], c)
        mu[j] = var"dL0.star"[j] * c # prior mean hazard

        # Survivor function = exp(-Integral{l0(u)du})^exp(beta*z)
        var"S.treat"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * -0.5))
        var"S.placebo"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * 0.5))
    end

    c = 0.001
    r = 0.1
    for j in 1:T
        var"dL0.star"[j] = r * (t[j + 1] - t[j])
    end
    beta ~ dnorm(0.0, 0.000001)
end
```

Names such as `var"obs.t"`, `var"dL0.star"`, `var"S.treat"`, and `var"S.placebo"` are the R-style dotted variable names from the original BUGS program, written with Julia's `var"..."` syntax so they can be kept exactly as they appear in the classic example.

## Data

The data are supplied as a `NamedTuple`: the number of patients `N`, the number of distinct failure times `T`, a small constant `eps` used in the risk-set comparisons, the observed times `obs.t` (in weeks), the failure indicator `fail`, the treatment covariate `Z` (coded $\pm 0.5$), and the grid of interval boundaries `t`.

```@example leuk
data = (
    N = 42,
    T = 17,
    eps = 1.0E-10,
    var"obs.t" = [
        1, 1, 2, 2, 3, 4, 4, 5, 5, 8, 8, 8, 8, 11, 11, 12, 12, 15, 17, 22, 23, 6,
        6, 6, 6, 7, 9, 10, 10, 11, 13, 16, 17, 19, 20, 22, 23, 25, 32, 32, 34, 35
    ],
    fail = [
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0
    ],
    Z = [
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5
    ],
    t = [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 22, 23, 35]
)

model = leuk(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`, so the model definition, data, and initial values above are also available directly as `JuliaBUGS.BUGSExamples.VOLUME_1.leuk`.

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = leuk(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.leuk.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censoring is handled by the counting-process formulation"
    This is a survival model with right-censored data: the `fail` indicator marks which observed times are true failures rather than censored follow-up times. Instead of a censored or truncated likelihood, the Cox model is recast in counting-process form, so censoring enters only through the risk-set indicators `Y` and the failure counts `dN`, and the likelihood reduces to an ordinary Poisson model over continuous parameters. No special censoring machinery or discrete latent variables are involved.

## Results

No reference posterior summaries ship with this example in `JuliaBUGS.BUGSExamples`. Published results for the quantities of interest, including the treatment effect `beta` and the survivor functions `S.treat` and `S.placebo`, are available on the [OpenBUGS page for this example](https://chjackson.github.io/openbugsdoc/Examples/Leuk.html), and a correctly converged chain's `summarystats` should reproduce them up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
