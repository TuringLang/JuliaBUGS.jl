# JuliaBUGS.jl

JuliaBUGS is a graph-based probabilistic programming framework inspired by the BUGS language.

Key features of JuliaBUGS include:

- Compatibility with existing BUGS programs
- Extensibility through user-defined functions and distributions; programmable inference
- Seamless integration with Julia's high-performance numerical and scientific computing libraries
- Automatic differentiation and sampling using Hamiltonian Monte Carlo

It's important to note that while BUGS traditionally refers to either the software system, the language, or the inference algorithm, JuliaBUGS is a pure Julia implementation of the BUGS language, not a wrapper for the BUGS system.

## Where do I start?

- **New to JuliaBUGS?** Begin with [Getting Started](getting_started.md).
- **Have existing WinBUGS, OpenBUGS, or JAGS models?** Read the [migration guide](guides/differences.md).
- **Coming from Turing.jl?** See the [orientation](migration/from_turing.md).
- **Working from R?** See the [R interface](R_interface.md).
- **Want worked models?** Browse the [Example Gallery](examples/index.md).
- **Prefer drawing the graph?** Try [DoodleBUGS](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/), a browser-based visual model builder.

## Understanding the BUGS Language

The BUGS (Bayesian inference Using Gibbs Sampling) language is designed for specifying directed graphical models in probabilistic programming. Unlike imperative probabilistic programming languages such as Turing.jl or Pyro, BUGS focuses on declarative relationships between nodes in a graph.

This graph-based approach offers several advantages:

1. Clarity: It provides a clear understanding of dependencies and relationships within complex systems.
2. Transparency: Users can explicitly state conditional dependencies between variables, making model structure and assumptions more transparent.
3. Ease of development and interpretation: The graphical representation aids in both model development and result interpretation.
4. Efficient inference: The graph structure facilitates the application of advanced inference algorithms, enabling more efficient computation by leveraging the model's structure.

By adopting this approach, JuliaBUGS aims to combine the clarity and power of graphical models with the performance and flexibility of the Julia programming language.
