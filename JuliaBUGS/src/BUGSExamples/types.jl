"""
    ReferenceResults

Reference posterior summaries for a BUGS example, plus provenance metadata.

`params` is a NamedTuple keyed by parameter name, each value a NamedTuple with
at least `mean` and `std` fields (CI runs may also include `ess`, `rhat`).
`meta` describes where the numbers came from — typically either
`source = "reference"` (literature values) or `source = "ci"` (resampled by
the BUGSExamples results workflow).
"""
struct ReferenceResults{P<:NamedTuple,M<:NamedTuple}
    params::P
    meta::M
end

"""
    BUGSExample

A BUGS example: model code in multiple representations, data, inits, and
optional reference results. Backed by a directory of plain files
(`model.bugs`, `model.jl`, `model_fn.jl`, `data.json`, `results.json`,
`meta.toml`) — see `BUGSExamples.path(ex, file)` to access the source files
directly.

`BUGSExamples` itself has no JuliaBUGS dependency; consumers parse the model
strings (or `include` `model.jl` / `model_fn.jl` with JuliaBUGS loaded) when
they need a compiled model.

# Fields
- `name::String` — human-readable title
- `description::String` — short prose blurb (may be empty)
- `citations::Vector{String}` — BibTeX keys (resolved via `docs/src/refs.bib`)
- `doodlebugs_id::Union{Nothing,String}` — id under `DoodleBUGS/public/examples/<id>/` if a graph exists
- `volume::Int` — BUGS volume number (1..4)
- `order::Int` — within-volume display order (lower = earlier; defaults to 999 if absent)
- `tags::Vector{String}`
- `original_syntax_program::String` — raw BUGS source (from `model.bugs`)
- `model_def::String` — `@bugs begin … end` source (from `model.jl`)
- `model_function::String` — `@model function … end` source (from `model_fn.jl`, `""` if absent)
- `stan_code::String` — Stan source (from `model.stan`, `""` if absent)
- `numpyro_code::String` — NumPyro source (from `model.py`, `""` if absent)
- `data::NamedTuple`
- `inits::NamedTuple`
- `inits_alternative::NamedTuple`
- `reference_results::Union{ReferenceResults,Nothing}` — literature-known summaries from `reference.json` if present
- `sampled_results::Union{ReferenceResults,Nothing}` — CI-sampled summaries from `results.json` if present
- `source_dir::String` — absolute path to the example directory
"""
struct BUGSExample{D<:NamedTuple,I<:NamedTuple,I2<:NamedTuple,R,S}
    name::String
    description::String
    citations::Vector{String}
    doodlebugs_id::Union{Nothing,String}
    volume::Int
    order::Int
    tags::Vector{String}
    original_syntax_program::String
    model_def::String
    model_function::String
    stan_code::String
    numpyro_code::String
    data::D
    inits::I
    inits_alternative::I2
    reference_results::R
    sampled_results::S
    source_dir::String
end

"""
    path(ex::BUGSExample, file::AbstractString) -> String

Absolute path to a source file inside the example's directory. Use this when
consumers (JuliaBUGS tests, benchmarks, doc templates) need to `include` or
read the source files directly:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats
model_expr = include(BUGSExamples.path(ex, "model.jl"))  # returns an Expr
```
"""
path(ex::BUGSExample, file::AbstractString) = joinpath(ex.source_dir, file)
