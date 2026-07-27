# LeukFr: Cox Regression with Random Effects

This example comes from Volume 1 of the classic [BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html), and is also documented on the [OpenBUGS Leukfr page](https://chjackson.github.io/openbugsdoc/Examples/Leukfr.html). The data are the well-known leukaemia remission times of Freireich et al. (1963): 42 patients arranged in 21 matched pairs, where within each pair one patient received the drug 6-mercaptopurine (6-MP) and the other received placebo. For each patient we observe a remission (survival) time `obs.t` and an indicator `fail` of whether the event was observed or the observation was censored, together with a treatment covariate `Z` (coded as ±0.5) and the pairing `pair`.

The question is whether 6-MP prolongs remission, while accounting for the fact that patients were matched in pairs. The model is a Cox proportional-hazards regression fitted through the counting-process (Poisson) representation used throughout the BUGS survival examples. It extends the plain Leuk model by adding a normally distributed **frailty** term `b[pair[i]]`, a random effect shared by the two patients in each matched pair, so that within-pair correlation is modelled explicitly. This is a random-effects (frailty) survival model.

## Model

At each observed failure time `t[j]` the counting-process increment `dN[i, j]` for patient `i` is treated as Poisson with an intensity that combines the treatment effect, the pair-specific frailty, and a baseline hazard increment `dL0[j]`:

```math
\begin{aligned}
dN_{ij} &\sim \text{Poisson}(I_{ij}) \\
I_{ij} &= Y_{ij}\,\exp(\beta\, Z_i + b_{\text{pair}(i)})\,dL0_j \\
b_k &\sim \text{Normal}(0, \tau) \\
dL0_j &\sim \text{Gamma}(\mu_j, c) \\
\beta &\sim \text{Normal}(0, 10^{-6}) \\
\tau &\sim \text{Gamma}(0.001, 0.001)
\end{aligned}
```

Here `Y[i, j]` is the risk-set indicator (1 if patient `i` is still at risk at time `t[j]`), built from the observed times using `step`. Some variables in the original program have R-style dotted names such as `obs.t`, `dL0.star`, `S.treat`, and `S.placebo`; these are written with Julia's `var"..."` syntax so the names carry over from the original BUGS program unchanged.

```@example leukfr
using JuliaBUGS

leukfr = @bugs begin # Set up data
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
            dN[i, j] ~ dpois(Idt[i, j])
            Idt[i, j] = Y[i, j] * exp(beta * Z[i] + b[pair[i]]) * dL0[j]
        end
        dL0[j] ~ dgamma(mu[j], c)
        mu[j] = var"dL0.star"[j] * c # prior mean hazard

        # Survivor function = exp(-Integral{l0(u)du})^exp(beta * z)
        var"S.treat"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * -0.5))
        var"S.placebo"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * 0.5))
    end
    for k in 1:Npairs
        b[k] ~ dnorm(0.0, tau)
    end
    tau ~ dgamma(0.001, 0.001)
    sigma = sqrt(1 / tau)
    c = 0.001
    r = 0.1
    for j in 1:T
        var"dL0.star"[j] = r * (t[j + 1] - t[j])
    end
    beta ~ dnorm(0.0, 0.000001)
end
```

## Data

The data give the study dimensions (`N` = 42 patients, `T` = 17 distinct failure times, `Npairs` = 21 matched pairs), the grid of failure times `t`, the observed remission times `obs.t`, the failure/censoring indicators `fail`, the pair labels `pair`, and the treatment covariate `Z`. We supply them as a `NamedTuple` and construct the model:

```@example leukfr
data = (
    N = 42,
    T = 17,
    eps = 0.00001,
    Npairs = 21,
    t = [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 22, 23, 35],
    var"obs.t" = [
        1, 1, 2, 2, 3, 4, 4, 5, 5, 8, 8, 8, 8, 11, 11, 12, 12, 15, 17, 22, 23, 6,
        6, 6, 6, 7, 9, 10, 10, 11, 13, 16, 17, 19, 20, 22, 23, 25, 32, 32, 34, 35
    ],
    pair = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        19, 18, 8, 1, 20, 6, 2, 10, 3, 14, 4, 11, 7, 9, 12, 16, 17, 5, 13, 15, 21
    ],
    fail = [
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0
    ],
    Z = [
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
        0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
        0.5, 0.5, 0.5, -0.5, -0.5, -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5
    ]
)

inits = JuliaBUGS.BUGSExamples.VOLUME_1.leukfr.inits
model = leukfr(data, inits)
```

We pass the example's published initial values as the second argument to `leukfr` rather than calling `leukfr(data)` alone: this counting-process (Poisson) survival model has vague priors, so values drawn at random from the priors can give an invalid rate, and a sensible starting point keeps construction and sampling stable.

All of the classic examples ship with the package under `JuliaBUGS.BUGSExamples`, each bundling the model definition, data, initial values, and reference results, so you can also load this one directly as `JuliaBUGS.BUGSExamples.VOLUME_1.leukfr`.

## Sampling

Construct the model with a gradient backend and draw posterior samples with the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = leukfr(data, inits; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.leukfr.inits` and can be applied with `initialize!(model, inits)`.

!!! note "Censored survival data via the counting-process representation"
    Like the other BUGS survival examples, this model does not handle the censored remission times directly. Instead it uses the counting-process (Poisson) representation: the risk-set indicators `Y[i, j]` and the increments `dN[i, j]` are computed deterministically from the observed times and the `fail` indicator, and the `dN[i, j]` are then treated as Poisson observations. There are no discrete latent variables to sample, so no special handling is required beyond the recipe above.

## Results

The source file ships `reference_results = nothing` for this example, so there is no tabulated reference posterior summary bundled with the package to reproduce here. For published numerical summaries of the treatment effect `beta` and the frailty standard deviation `sigma` (obtained after a 1,000-iteration burn-in followed by 10,000 further updates), see the [OpenBUGS Leukfr page](https://chjackson.github.io/openbugsdoc/Examples/Leukfr.html). A correctly converged chain's `summarystats` output should match those published values up to Monte Carlo error.

See also: the [gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
