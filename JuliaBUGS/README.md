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
pkg> add JuliaBUGS
```

The HMC example also requires its sampling and differentiation packages:

```julia-repl
pkg> add AbstractMCMC ADTypes AdvancedHMC Distributions Mooncake
```

## Example

The `@model` macro defines a function that compiles a model when called. Its first argument
declares every stochastic variable. Values supplied in that named tuple are observed;
omitted values remain latent. Subsequent arguments are fixed inputs.

```julia
using AbstractMCMC
using ADTypes: AutoMooncake
using AdvancedHMC: HMC
using Distributions: Normal
using JuliaBUGS
using Random
import Mooncake

@model function normal_location((; y, μ), σ, N)
    μ ~ Normal(0, 10)
    for i in 1:N
        y[i] ~ Normal(μ, σ)
    end
end

y = [1.2, 0.9, 1.4, 1.1, 0.7]
model = normal_location((; y), 1.0, length(y))
posterior = JuliaBUGS.BUGSModelWithGradient(
    model, AutoMooncake(; config = nothing)
)

rng = MersenneTwister(42)
sampler = HMC(0.1, 10)
draws = sample(
    rng, posterior, sampler, 2_000;
    n_adapts = 500, discard_initial = 500, progress = false,
)
```

The call returns 2,000 posterior draws after 500 adaptation iterations. Each draw contains
parameter values and sampler diagnostics. Substantive analyses should use multiple chains
and assess convergence before interpreting posterior summaries.

For existing BUGS programs, the
[`@bugs` interface](https://turinglang.org/JuliaBUGS.jl/stable/two_macros/) accepts traditional
BUGS notation, including models migrated from WinBUGS, OpenBUGS, or JAGS.

## Repository structure

- `JuliaBUGS/` contains the Julia package, tests, documentation, examples, and benchmarks.
- `DoodlePPL/` contains the static deployment of the browser-based graph editor.

## Documentation

The [manual](https://turinglang.org/JuliaBUGS.jl/stable/) covers model construction,
initialisation, automatic differentiation, inference, generated quantities, and migration
from other BUGS implementations.

JuliaBUGS is distributed under the MIT License.
