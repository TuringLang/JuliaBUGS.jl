```@raw html
---
layout: home

hero:
  name: "JuliaBUGS.jl"
  text: "Graph-based Probabilistic Programming"
  tagline: A pure-Julia implementation of the BUGS language with Hamiltonian Monte Carlo, automatic differentiation, and a curated collection of classical examples.
  image:
    src: https://turinglang.org/assets/logo/turing-logo.svg
    alt: TuringLang
  actions:
    - theme: brand
      text: Get Started
      link: /example
    - theme: alt
      text: Browse Examples
      link: /examples/rats
    - theme: alt
      text: View on GitHub
      link: https://github.com/TuringLang/JuliaBUGS.jl

features:
  - title: Compatible with BUGS
    details: Run existing BUGS programs without modification, alongside the modern @bugs and @model macros for Julia-native model definitions.
  - title: Programmable Inference
    details: HMC via AdvancedHMC, independent MH, Gibbs, and full integration with the SciML and AbstractMCMC ecosystem.
  - title: Classical Examples Included
    details: BUGSExamples ships with the Volume 1 corpus — model, data, inits, and reference posterior summaries — usable for benchmarks and tutorials.
---
```

```@meta
CurrentModule = JuliaBUGS
```

## What is JuliaBUGS?

JuliaBUGS is a graph-based probabilistic programming framework inspired by the BUGS language. It compiles BUGS or `@bugs`/`@model` Julia syntax into a typed graph model that supports HMC and other samplers via [AbstractMCMC.jl](https://github.com/TuringLang/AbstractMCMC.jl). BUGS traditionally refers to the software system, the language, or the inference algorithm; JuliaBUGS is a pure Julia implementation of the language — not a wrapper around the original system.

## Key features

- Compatibility with existing BUGS programs (parse and compile from the original syntax).
- Three model-definition surfaces: the `@bugs(str)` parser, the `@bugs begin … end` macro, and `@model function … end` with full Julia scope.
- Automatic differentiation through DifferentiationInterface (ForwardDiff / ReverseDiff / Enzyme / Mooncake).
- Hamiltonian Monte Carlo via AdvancedHMC, independent MH, Gibbs sampling, and parallel/distributed chain support.
- A curated collection of classical examples (`JuliaBUGS.BUGSExamples`) with multi-language source files (BUGS, `@bugs`, `@model`, Stan-pending), reference posterior summaries, and interactive DoodleBUGS graphs in the docs.

## Understanding the BUGS language

The BUGS (Bayesian inference Using Gibbs Sampling) language is designed for specifying directed graphical models. Unlike imperative probabilistic programming languages such as Turing.jl or Pyro, BUGS focuses on declarative relationships between nodes in a graph. This graph-based approach offers several advantages:

1. **Clarity**: dependencies and relationships are visible in the model text itself.
2. **Transparency**: conditional dependencies between variables are explicit, making model structure and assumptions auditable.
3. **Ease of development**: graphical representations aid both model development and result interpretation.
4. **Efficient inference**: the graph structure exposes conditional independencies that downstream samplers can exploit.

JuliaBUGS combines the clarity and power of graphical models with the performance and flexibility of the Julia programming language.
