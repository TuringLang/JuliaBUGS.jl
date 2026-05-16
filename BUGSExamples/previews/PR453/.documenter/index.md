---
layout: home

hero:
  name: "BUGSExamples.jl"
  text: "Classical BUGS Models"
  tagline: A collection of classical BUGS examples with multi-language model representations and interactive DoodleBUGS graphs
  image:
    src: https://turinglang.org/assets/logo/turing-logo.svg
    alt: TuringLang
  actions:
    - theme: brand
      text: Browse Examples
      link: /generated/rats
    - theme: alt
      text: View on GitHub
      link: https://github.com/TuringLang/JuliaBUGS.jl

features:
  - title: Multiple Representations
    details: Each model ships as separate files — model.bugs, model.jl (@bugs), model_fn.jl (@model), and optionally Stan / NumPyro
  - title: DoodleBUGS Graphs
    details: Interactive graphical-model visualizations powered by DoodleBUGS where available
  - title: No JuliaBUGS Dependency
    details: BUGSExamples reads model source files as strings — load it alongside JuliaBUGS only when you want to compile and run
---




## Quick Start {#Quick-Start}

```julia
using BUGSExamples

# Browse all available examples
BUGSExamples.list()

# Access an example
ex = BUGSExamples.rats
println(ex.original_syntax_program)   # raw BUGS source
println(ex.data)                       # data as NamedTuple
```


## Using with JuliaBUGS {#Using-with-JuliaBUGS}

BUGSExamples has **no JuliaBUGS dependency**. When you want to compile and run a model:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats

# Option 1 — parse the raw BUGS string
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)

# Option 2 — include the Julia model file (returns an Expr)
model_def = include(BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```


## What&#39;s in each example {#What's-in-each-example}

Every model directory under `BUGSExamples/src/<name>/` contains:

|                      File |                                                                    Purpose |
| -------------------------:| --------------------------------------------------------------------------:|
|               `meta.toml` |                         name, description, references, doodlebugs id, tags |
|              `model.bugs` |                                          raw BUGS syntax (`model { ... }`) |
|                `model.jl` |                           JuliaBUGS `@bugs begin … end` form (valid Julia) |
|             `model_fn.jl` |                          JuliaBUGS `@model function … end` form (optional) |
| `model.stan` / `model.py` |                                           Stan / NumPyro source (optional) |
|               `data.json` |                                           data + inits + alternative inits |
|          `reference.json` |                    literature posterior summaries (optional, hand-curated) |
|            `results.json` | CI-sampled posterior summaries (optional, written by the results workflow) |


Use `BUGSExamples.path(ex, "model.jl")` to get the absolute path to any source file.

## Available Examples {#Available-Examples}

Browse the sidebar to view all available examples grouped by volume, or call `BUGSExamples.list()` from the REPL.
