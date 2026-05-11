```@raw html
---
layout: home

hero:
  name: "BUGSExamples.jl"
  text: "Classical BUGS Models"
  tagline: A collection of classical BUGS examples with multi-language model representations and interactive DoodleBUGS graphs
  actions:
    - theme: brand
      text: Browse Examples
      link: /generated/rats
    - theme: alt
      text: View on GitHub
      link: https://github.com/TuringLang/JuliaBUGS.jl

features:
  - title: Multiple Representations
    details: Each model includes original BUGS syntax, JuliaBUGS @bugs macro, and @model macro forms
  - title: DoodleBUGS Graphs
    details: Interactive graphical model visualizations powered by DoodleBUGS where available
  - title: No JuliaBUGS Dependency
    details: All model code is stored as plain strings — use the package as a reference library or pass directly to JuliaBUGS
---
```

```@meta
CurrentModule = BUGSExamples
```

## Quick Start

```julia
using BUGSExamples

# Browse all available examples
BUGSExamples.list()

# Access an example
ex = BUGSExamples.rats
println(ex.original_syntax_program)   # Original BUGS model
println(ex.data)                       # Data
```

## Using with JuliaBUGS

BUGSExamples has **no JuliaBUGS dependency**. When you want to compile and run a model,
simply pass the model string to JuliaBUGS's `@bugs` macro:

```julia
using JuliaBUGS, BUGSExamples

ex = BUGSExamples.rats

# Parse the BUGS string into a model definition
model_def = @bugs(ex.original_syntax_program)

# Compile the model
model = compile(model_def, ex.data, ex.inits)
```

## Available Examples

Browse the sidebar to view all available examples grouped by volume.

| Field | Description |
|-------|-------------|
| `original_syntax_program` | Original BUGS syntax (`model{...}` string) |
| `model_def` | JuliaBUGS `@bugs begin...end` Julia expression syntax |
| `model_function` | JuliaBUGS `@model function...end` syntax |
| `data` | Model data as a NamedTuple |
| `inits` | Initial parameter values |
| `reference_results` | Reference posterior results |
