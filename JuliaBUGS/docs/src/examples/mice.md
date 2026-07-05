# Mice: Weibull Regression

This example analyses survival data from a photocarcinogenicity experiment, taken from Grieve (1987). Four treatment groups of 20 mice each were followed over time, and for each animal the survival time (in weeks) was recorded. Some animals were still alive when the study ended, so their survival times are *right-censored*: we only know that the animal lived at least as long as its recorded follow-up time, not exactly how long it would have survived.

The goal is to describe how survival varies across the four treatment groups. Survival times are modelled with a Weibull distribution whose shape parameter `r` is shared across all animals and whose scale depends on the animal's treatment group through a group-specific coefficient `beta`. This is a Weibull regression (accelerated-failure-time style) survival model with censored observations. From the group coefficients the model derives the median survival time in each group and a set of contrasts comparing the three active treatments against the first (control) group.

This is one of the classic examples from Volume 1 of the BUGS examples; see the [MultiBUGS Volume I collection](https://www.multibugs.org/examples/latest/VolumeI.html) and the matching [OpenBUGS Mice page](https://chjackson.github.io/openbugsdoc/Examples/Mice.html).

## Model

Writing $r$ for the shared Weibull shape, $\beta_i$ for the coefficient of group $i$, and $\mu_i = \exp(\beta_i)$ for the corresponding Weibull scale parameter, the model is

```math
\begin{aligned}
t_{ij} &\sim \text{Weibull}(r, \mu_i) \quad \text{(right-censored at } t^{\text{cen}}_{ij}) \\
\mu_i &= \exp(\beta_i) \\
\beta_i &\sim \text{Normal}(0, 0.001) \\
\text{median}_i &= \big(\log 2 \cdot \exp(-\beta_i)\big)^{1/r} \\
r &\sim \text{Uniform}(0.1, 10)
\end{aligned}
```

where the Normal prior on each $\beta_i$ is written in BUGS' mean/precision parameterisation (precision $0.001$).

```@example mice
using JuliaBUGS
using Distributions

# `censored` comes from Distributions; make it available inside `@bugs`:
JuliaBUGS.@bugs_primitive censored

mice = @bugs begin
    for i in 1:M
        for j in 1:N
            t[i, j] ~ censored(dweib(r, mu[i]), var"t.cen"[i, j], nothing)
        end
        mu[i] = exp(beta[i])
        beta[i] ~ dnorm(0.0, 0.001)
        median[i] = pow(log(2) * exp(-(beta[i])), 1 / r)
    end

    # r ~ dexp(0.001)
    r ~ dunif(0.1, 10)
    var"veh.control" = beta[2] - beta[1]
    var"test.sub" = beta[3] - beta[1]
    var"pos.control" = beta[4] - beta[1]
end
```

The names `var"t.cen"`, `var"veh.control"`, `var"test.sub"`, and `var"pos.control"` are R-style dotted names carried over verbatim from the original BUGS program; Julia allows such non-standard identifiers through its `var"..."` syntax.

## Data

The data hold the survival times and censoring information for the `M = 4` groups of `N = 20` mice each. In the `t` matrix, a `missing` entry marks an animal whose survival time was censored; the corresponding entry of `var"t.cen"` gives the time at which that animal was last known to be alive (a value of `0` means the animal's survival time was observed exactly).

```@example mice
data = (
    t = [12 1 21 25 11 26 27 30 13 12 21 20 23 25 23 29 35 missing 31 36
         32 27 23 12 18 missing missing 38 29 30 missing 32 missing missing missing missing 25 30 37 27
         22 26 missing 28 19 15 12 35 35 10 22 18 missing 12 missing missing 31 24 37 29
         27 18 22 13 18 29 28 missing 16 22 26 19 missing missing 17 28 26 12 17 26],
    var"t.cen" = [0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 40 0 0
                  0 0 0 0 0 40 40 0 0 0 40 0 40 40 40 40 0 0 0 0
                  0 0 10 0 0 0 0 0 0 0 0 0 24 0 40 40 0 0 0 0
                  0 0 0 0 0 0 0 20 0 0 0 0 29 10 0 0 0 0 0 0],
    M = 4,
    N = 20
)

model = mice(data)
```

All of the classic examples ship with the package inside `JuliaBUGS.BUGSExamples` — each entry bundles the model definition, data, initial values, and reference results, so you can load `JuliaBUGS.BUGSExamples.VOLUME_1.mice` directly instead of retyping the data above.

## Sampling

With the model constructed, we attach an automatic-differentiation backend and draw posterior samples with the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = mice(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.mice.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censored observations"
    Several survival times in this example are right-censored: the animal was still alive when the study ended, so its exact survival time is unknown and only known to exceed the recorded follow-up time. The `censored(dweib(r, mu[i]), var"t.cen"[i, j], nothing)` term encodes this — for a censored animal the likelihood contribution is the Weibull survival probability beyond `var"t.cen"[i, j]` rather than a density at an observed time. This is handled automatically during sampling; you do not need to treat the censored entries specially.

## Results

Unlike some of the other Volume 1 examples, this one does not ship with a tabulated reference posterior summary — `JuliaBUGS.BUGSExamples.VOLUME_1.mice.reference_results` is `nothing`, so there are no stored means and standard deviations to reproduce here. The published estimates for the shape parameter `r`, the group medians, and the treatment contrasts are reported on the [OpenBUGS Mice page](https://chjackson.github.io/openbugsdoc/Examples/Mice.html) (obtained there from a burn-in of 1000 updates followed by 10000 further updates). Once your chain has converged, the posterior means and standard deviations from `summarystats(chain)` should agree with those published values up to Monte Carlo error.

See also: the [Example Gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
