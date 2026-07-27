# Epilepsy: Repeated Measures on Poisson Counts

Breslow and Clayton (1993) analysed data originally reported by Thall and Vail (1990) on seizure counts from a randomised trial of anti-convulsant therapy in epilepsy. Fifty-nine patients were followed over four successive clinic visits, and the number of seizures in the interval before each visit was recorded, along with each patient's treatment assignment, baseline seizure count, and age. The question is whether the treatment reduces the seizure rate after adjusting for these covariates.

The model is a Poisson generalised linear mixed model (model III of Breslow and Clayton). The log seizure rate is a linear function of centred covariates — log baseline count, treatment, a treatment-by-baseline interaction, log age, and an indicator for the fourth visit — plus a subject-level random effect and a subject-by-visit random effect that allows for extra-Poisson variation. This example is from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS documentation page](https://chjackson.github.io/openbugsdoc/Examples/Epil.html).

## Model

For patient ``j = 1, \dots, 59`` and visit ``k = 1, \dots, 4``,

```math
\begin{aligned}
y_{jk} &\sim \text{Poisson}(\mu_{jk}) \\
\log \mu_{jk} &= a_0
  + \alpha_{\text{Base}} \left( \log(\text{Base}_j / 4) - \overline{\log(\text{Base}/4)} \right)
  + \alpha_{\text{Trt}} \left( \text{Trt}_j - \overline{\text{Trt}} \right)
  + \alpha_{\text{BT}} \left( \text{BT}_j - \overline{\text{BT}} \right) \\
  &\quad + \alpha_{\text{Age}} \left( \log(\text{Age}_j) - \overline{\log(\text{Age})} \right)
  + \alpha_{\text{V4}} \left( \text{V4}_k - \overline{\text{V4}} \right)
  + b1_j + b_{jk} \\
b1_j &\sim \text{Normal}(0, \sigma_{b1}^2), \qquad
b_{jk} \sim \text{Normal}(0, \sigma_b^2)
\end{aligned}
```

with vague normal priors on the coefficients and vague gamma priors on the random-effect precisions. The original BUGS program uses R-style dotted names such as `alpha.Base` and `tau.b`; in Julia these are written with the `var"..."` syntax, which lets a variable name contain a dot.

```@example epil
using JuliaBUGS

epil = @bugs begin
    for j in 1:N
        for k in 1:T
            mu[j, k] = exp(
                a0 + var"alpha.Base" * (var"log.Base4"[j] - var"log.Base4.bar") +
                var"alpha.Trt" * (Trt[j] - var"Trt.bar") +
                var"alpha.BT" * (BT[j] - var"BT.bar") +
                var"alpha.Age" * (var"log.Age"[j] - var"log.Age.bar") +
                var"alpha.V4" * (V4[k] - var"V4.bar") + b1[j] + b[j, k]
            )
            y[j, k] ~ dpois(mu[j, k])
            b[j, k] ~ dnorm(0.0, var"tau.b")       # subject*visit random effects
        end
        b1[j] ~ dnorm(0.0, var"tau.b1")        # subject random effects
        BT[j] = Trt[j] * var"log.Base4"[j]    # interaction
        var"log.Base4"[j] = log(Base[j] / 4)
        var"log.Age"[j] = log(Age[j])
    end

    # covariate means:
    var"log.Age.bar" = mean(var"log.Age"[:])
    var"Trt.bar" = mean(Trt[:])
    var"BT.bar" = mean(BT[:])
    var"log.Base4.bar" = mean(var"log.Base4"[:])
    var"V4.bar" = mean(V4[:])

    # priors:
    a0 ~ dnorm(0.0, 1.0E-4)
    var"alpha.Base" ~ dnorm(0.0, 1.0E-4)
    var"alpha.Trt" ~ dnorm(0.0, 1.0E-4)
    var"alpha.BT" ~ dnorm(0.0, 1.0E-4)
    var"alpha.Age" ~ dnorm(0.0, 1.0E-4)
    var"alpha.V4" ~ dnorm(0.0, 1.0E-4)
    var"tau.b1" ~ dgamma(1.0E-3, 1.0E-3)
    var"sigma.b1" = 1.0 / sqrt(var"tau.b1")
    var"tau.b" ~ dgamma(1.0E-3, 1.0E-3)
    var"sigma.b" = 1.0 / sqrt(var"tau.b")

    # re-calculate intercept on original scale: 
    alpha0 = a0 - var"alpha.Base" * var"log.Base4.bar" - var"alpha.Trt" * var"Trt.bar" -
             var"alpha.BT" * var"BT.bar" - var"alpha.Age" * var"log.Age.bar" -
             var"alpha.V4" * var"V4.bar"
end
```

## Data

The data set is too large to display comfortably here, so we load it from the copy that ships with JuliaBUGS. It contains `N = 59` patients and `T = 4` visits, the `59 × 4` matrix `y` of seizure counts, the treatment indicator `Trt` (0 = placebo, 1 = active treatment), the baseline seizure count `Base`, each patient's `Age` in years, and `V4`, an indicator that equals 1 only at the fourth visit.

```@example epil
data  = JuliaBUGS.BUGSExamples.VOLUME_1.epil.data
inits = JuliaBUGS.BUGSExamples.VOLUME_1.epil.inits
model = epil(data, inits)
```

We pass the example's published initial values as the second argument to `epil` rather than calling `epil(data)` alone. This is a log-linear Poisson model with vague priors, so values drawn at random from the priors can produce an invalid (non-positive or overflowing) rate; starting from sensible values keeps construction and sampling stable.

All of the classic Volume 1 examples ship with the package in `JuliaBUGS.BUGSExamples`, each providing the model definition, data, initial values, and reference results.

## Sampling

To draw posterior samples, we build the model with gradient support and run the NUTS sampler from AdvancedHMC:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = epil(data, inits; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.epil.inits` and can be applied with `initialize!(model, inits)`.

## Results

JuliaBUGS does not ship reference results for this example. For published estimates, see the [OpenBUGS documentation page](https://chjackson.github.io/openbugsdoc/Examples/Epil.html), which reports results alongside the approximate-likelihood fit of Breslow and Clayton (1993); a correctly converged chain's `summarystats` should agree with those values up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting started tutorial](../getting_started.md).
