# JuliaBUGS.jl
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://TuringLang.github.io/JuliaBUGS.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://TuringLang.github.io/JuliaBUGS.jl/dev)

**JuliaBUGS.jl** is a modern, high-performance implementation of the [BUGS](https://en.wikipedia.org/wiki/WinBUGS) probabilistic programming language in [Julia](https://julialang.org/). It brings the familiar BUGS modelling syntax into the Julia ecosystem, enabling Bayesian inference with speed, flexibility, and seamless integration with the scientific computing ecosystem in Julia.

---

## Why JuliaBUGS?

-   **BUGS syntax** — write models using standard BUGS notation.
    
-   **Julia performance** — leverage Julia’s speed and just-in-time (JIT) compilation.
    
-   **Interoperability with Julia ecosystem** — works smoothly with MCMC algrorithms from [Turing.jl](https://turinglang.org/) and the broader Julia PPL ecosystem.   

---

## Quick Start

A simple example model:

```julia
using JuliaBUGS, Random, AbstractMCMC

model = JuliaBUGS.@bugs"""
model {
  for (i in 1:N) {
    y[i] ~ dnorm(mu, tau)
  }
  mu ~ dnorm(0, 0.001)
  tau ~ dgamma(0.1, 0.1)
}
"""

posterior = compile(model, (; N = 10, y = randn(10)))
rng, sampler = Random.MersenneTwister(123), JuliaBUGS.IndependentMH()

chain = AbstractMCMC.sample(rng, posterior, sampler, 1000)
```

For a complete walkthrough, see the [example](https://turinglang.org/JuliaBUGS.jl/stable/example).

---

## **Related Tools**

- [**DoodleBUGS**](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/) — a browser-based interface for drawing BUGS models.
- [**RJuliaBUGS**](https://mateusmaiads.github.io/rjuliabugs/) — an R interface to JuliaBUGS.
    
For alternative BUGS-family tools, see [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and [Nimble](https://r-nimble.org/).
