```@meta
CurrentModule = BUGSExamples
```

# BUGSExamples.jl

A standalone Julia package containing classical BUGS example models with
multi-language representations.

## Overview

BUGSExamples provides a collection of example models from the classic BUGS project
(Bayesian inference Using Gibbs Sampling). Each example includes the model code in
multiple formats:

| Field | Description |
|-------|-------------|
| `original_syntax_program` | Original BUGS syntax (`model{...}` string) |
| `model_def` | JuliaBUGS `@bugs begin...end` Julia expression syntax |
| `model_function` | JuliaBUGS `@model function...end` syntax |
| `stan_code` | Stan model code |
| `numpyro_code` | NumPyro/Python model code |
| `data` | Model data as a NamedTuple |
| `inits` | Initial parameter values |
| `inits_alternative` | Alternative initial values |
| `reference_results` | Reference posterior results |

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
