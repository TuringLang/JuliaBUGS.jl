# BUGSExamples Submodule

The `JuliaBUGS.BUGSExamples` submodule ships classical BUGS example models with multi-language source files (`model.bugs`, `model.jl`, `model_fn.jl`, optional `model.stan` / `model.py`), data, inits, and reference posterior summaries. Examples live under `JuliaBUGS/src/BUGSExamples/Volume_<n>/<name>/`.

## Types

```@docs
JuliaBUGS.BUGSExamples.BUGSExample
JuliaBUGS.BUGSExamples.ReferenceResults
```

## Functions

```@docs
JuliaBUGS.BUGSExamples.examples
JuliaBUGS.BUGSExamples.list
JuliaBUGS.BUGSExamples.path
JuliaBUGS.BUGSExamples.load_example
```

## Module

```@docs
JuliaBUGS.BUGSExamples.BUGSExamples
```
