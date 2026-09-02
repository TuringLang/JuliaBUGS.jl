# JuliaBUGS.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://TuringLang.github.io/JuliaBUGS.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://TuringLang.github.io/JuliaBUGS.jl/dev)

JuliaBUGS is a probabilistic programming system for Bayesian models represented as directed
graphs. It compiles each model into an explicit dependency graph used for initialisation,
log-density evaluation, conditioning, and inference. This representation supports both the
analysis of established BUGS models and research on graph-aware inference methods.

JuliaBUGS implements the AbstractPPL, AbstractMCMC, and LogDensityProblems interfaces in the
Turing ecosystem. Package extensions provide automatic differentiation, gradient-based and
component-wise samplers, and MCMCChains or FlexiChains output.

[DoodlePPL](https://turinglang.org/JuliaBUGS.jl/DoodlePPL/), developed from DoodleBUGS,
provides a browser-based graph editor that generates BUGS and Stan programs.
[RJuliaBUGS](https://mateusmaiads.github.io/rjuliabugs/) makes JuliaBUGS available from R.

## Installation

```julia-repl
pkg> add JuliaBUGS FlexiChains
```

## Example

The `@model` macro defines a function that compiles a model when called. Its first argument
declares every stochastic variable. Values supplied in that named tuple are observed;
omitted values remain latent.

```julia
using JuliaBUGS
using JuliaBUGS: AbstractMCMC, EnumeratedSampler, Gibbs, OrderedDict
using JuliaBUGS.AdvancedMH: RobustAdaptiveMetropolis
using JuliaBUGS.Distributions: Categorical, Gamma, Normal
using FlexiChains: VNChain, summarystats
using Random: MersenneTwister

@model function gaussian_mixture((; y, z, mu, tau), weights, prior_mean, K, N)
    for k in 1:K
        tau[k] ~ Gamma(2, 1 / 2)
        mu[k] ~ Normal(prior_mean[k], inv(sqrt(2 * tau[k])))
        sigma2[k] = inv(tau[k])
    end
    for i in 1:N
        z[i] ~ Categorical(weights)
        y[i] ~ Normal(mu[z[i]], inv(sqrt(tau[z[i]])))
    end
end

y = [-2.1, -1.8, 0.0, 0.2, 2.8, 3.1]
weights = fill(1 / 3, 3)
prior_mean = [-2.0, 0.0, 3.0]
model = gaussian_mixture((; y), weights, prior_mean, 3, length(y))
sampler = Gibbs(
    model,
    OrderedDict(
        @varname(z) => EnumeratedSampler(),
        [@varname(mu), @varname(tau)] => RobustAdaptiveMetropolis(),
    ),
)
draws = AbstractMCMC.sample(
    MersenneTwister(42),
    model,
    sampler,
    AbstractMCMC.MCMCSerial(),
    10_000,
    4;
    discard_initial = 2_000, progress = false, chain_type = VNChain,
)
summarystats(draws)
```

<details>
<summary>Equivalent WinBUGS-syntax example</summary>

```julia
using JuliaBUGS
using JuliaBUGS: AbstractMCMC, EnumeratedSampler, Gibbs, OrderedDict
using JuliaBUGS.AdvancedMH: RobustAdaptiveMetropolis
using FlexiChains: VNChain, summarystats
using Random: MersenneTwister

gaussian_mixture = @bugs("""
model {
    for (k in 1:K) {
        tau[k] ~ dgamma(2, 2)
        mu[k] ~ dnorm(prior_mean[k], 2 * tau[k])
        sigma2[k] <- 1 / tau[k]
    }
    for (i in 1:N) {
        z[i] ~ dcat(weights[])
        y[i] ~ dnorm(mu[z[i]], tau[z[i]])
    }
}
""")

y = [-2.1, -1.8, 0.0, 0.2, 2.8, 3.1]
weights = fill(1 / 3, 3)
prior_mean = [-2.0, 0.0, 3.0]
model = gaussian_mixture((; y, weights, prior_mean, K=3, N=length(y)))
sampler = Gibbs(
    model,
    OrderedDict(
        @varname(z) => EnumeratedSampler(),
        [@varname(mu), @varname(tau)] => RobustAdaptiveMetropolis(),
    ),
)
draws = AbstractMCMC.sample(
    MersenneTwister(42),
    model,
    sampler,
    AbstractMCMC.MCMCSerial(),
    10_000,
    4;
    discard_initial = 2_000, progress = false, chain_type = VNChain,
)
summarystats(draws)
```

</details>

The component-specific prior means make the labels identifiable. The Gamma prior on each
precision is equivalent to an inverse-gamma prior on `sigma2`.
`EnumeratedSampler` draws the allocation indicators exactly from their finite full
conditional. `RobustAdaptiveMetropolis` updates the component means and precisions as one
continuous block. The call returns four `VNChain` chains; inspect `summarystats(draws)` before
interpreting posterior summaries.

For existing BUGS programs, the
[`@bugs` interface](https://turinglang.org/JuliaBUGS.jl/stable/two_macros/) accepts traditional
BUGS notation, including models migrated from
[WinBUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs-project), OpenBUGS, JAGS, or
[NIMBLE](https://r-nimble.org/).

## Repository structure

- `JuliaBUGS/` contains the Julia package, tests, documentation, examples, and benchmarks.
- `DoodlePPL/` contains the static deployment of the browser-based graph editor.

## Documentation

The [manual](https://turinglang.org/JuliaBUGS.jl/stable/) covers model construction,
initialisation, automatic differentiation, inference, generated quantities, and migration
from other BUGS implementations.

JuliaBUGS is distributed under the MIT License.
