# Kidney: Weibull Regression with Random Effects

This example comes from Volume 1 of the classic [BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) and is also documented in the [OpenBUGS Kidney example](https://chjackson.github.io/openbugsdoc/Examples/Kidney.html). The data, from McGilchrist and Aisbett (1991), record the times to first and second recurrence of infection in 38 kidney patients on dialysis. Each patient contributes up to two observations, and some of those times are *censored*: for a censored observation we only know that the patient had gone a certain length of time without a recurrence, not the exact recurrence time.

The question is how the risk of recurrence depends on patient characteristics: age, sex, and the type of underlying disease (coded as "other", GN, AN, or PKD). The model is a Weibull survival regression with a patient-level random effect, so that the two observations from the same patient are allowed to be correlated and unexplained differences between patients are absorbed by a normally distributed "frailty" term. This is the classic Bayesian analogue of a shared-frailty proportional-hazards survival model.

## Model

For patient ``i`` and recurrence ``j``, the recurrence time ``t_{ij}`` follows a Weibull distribution whose scale depends on the covariates through a log link, with a per-patient random effect ``b_i``:

```math
\begin{aligned}
t_{ij} &\sim \text{Weibull}(r,\ \mu_{ij}), \quad \text{censored below by } t^{\text{cen}}_{ij} \\
\log \mu_{ij} &= \alpha + \beta_{\text{age}}\, \text{age}_{ij} + \beta_{\text{sex}}\, \text{sex}_i + \beta_{\text{dis}[\text{disease}_i]} + b_i \\
b_i &\sim \text{Normal}(0,\ \tau)
\end{aligned}
```

The disease effect uses a corner-point constraint: the first level is fixed to zero and the remaining three levels are estimated. All regression coefficients get flat normal priors, the random-effect precision ``\tau`` and the Weibull shape ``r`` get gamma priors, and ``\sigma = 1/\sqrt{\tau}`` is the standard deviation of the random effects.

```@example kidney
using JuliaBUGS
using Distributions

# `censored` comes from Distributions; make it available inside `@bugs`:
JuliaBUGS.@bugs_primitive censored

kidney = @bugs begin
    for i in 1:N
        for j in 1:M
            # Survival times bounded below by censoring times:
            t[i, j] ~ censored(dweib(r, mu[i, j]), var"t.cen"[i, j], nothing)
            mu[i, j] = exp(alpha + var"beta.age" * age[i, j] + var"beta.sex" * sex[i] +
                           var"beta.dis"[disease[i]] + b[i])
        end
        # Random effects:
        b[i] ~ dnorm(0.0, tau)
    end

    # Priors:
    alpha ~ dnorm(0.0, 0.0001)
    var"beta.age" ~ dnorm(0.0, 0.0001)
    var"beta.sex" ~ dnorm(0.0, 0.0001)
    # beta.dis[1] <- 0; # corner-point constraint
    for k in 2:4
        var"beta.dis"[k] ~ dnorm(0.0, 0.0001)
    end
    tau ~ dgamma(1.0E-3, 1.0E-3)
    r ~ dgamma(1.0, 1.0E-3)
    sigma = 1 / sqrt(tau) # s.d. of random effects
end
```

Names such as `var"beta.age"` and `var"t.cen"` are R-style dotted variable names carried over verbatim from the original BUGS program; Julia's `var"..."` syntax lets us keep the exact original names.

## Data

The data set is large, so we load the bundled copy rather than typing it out:

```@example kidney
data  = JuliaBUGS.BUGSExamples.VOLUME_1.kidney.data
inits = JuliaBUGS.BUGSExamples.VOLUME_1.kidney.inits
model = kidney(data, inits)
```

We pass the example's published initial values as the second argument to `kidney` rather than calling `kidney(data)` alone: with a censored survival likelihood and vague priors, values drawn at random from the priors can land outside the valid range, so a sensible starting point makes construction and sampling reliable.

Here `N = 38` is the number of patients and `M = 2` is the maximum number of recurrences per patient. `t` holds the recurrence times (with `missing` entries where the observation is censored), `t.cen` holds the corresponding censoring times, `age` is the patient's age at each observation, `sex` is a 0/1 indicator, and `disease` codes the underlying disease type as an integer from 1 to 4. All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`, bundling the model, data, initial values, and reference results together.

## Sampling

With the model compiled, we attach a gradient backend and draw posterior samples with the No-U-Turn Sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = kidney(data, inits; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.kidney.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censored observations"
    Several recurrence times in this data set are censored — we know only that the patient had gone at least `t.cen` days without a recurrence. This is expressed in the model with `censored(dweib(r, mu[i, j]), var"t.cen"[i, j], nothing)`, which lower-censors the Weibull distribution at the recorded censoring time. JuliaBUGS handles the censored likelihood automatically, so no special sampler setup is required.

## Results

The source file for this example ships with `reference_results = nothing`, so there is no bundled table of published posterior summaries to reproduce here. The MultiBUGS and OpenBUGS pages linked above report posterior means and standard deviations for `alpha`, `beta.age`, `beta.sex`, the disease effects `beta.dis[2]`–`beta.dis[4]`, the Weibull shape `r`, and the random-effect standard deviation `sigma`, obtained from a 1000-iteration burn-in followed by 10000 further iterations. A correctly converged chain's `summarystats` output should match those published values up to Monte Carlo error.

See also: the [gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
