
# BUGSExamples Submodule {#BUGSExamples-Submodule}

The `JuliaBUGS.BUGSExamples` submodule ships classical BUGS example models with multi-language source files (`model.bugs`, `model.jl`, `model_fn.jl`, optional `model.stan` / `model.py`), data, inits, and reference posterior summaries. Examples live under `JuliaBUGS/src/BUGSExamples/Volume_<n>/<name>/`.

## Types {#Types}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.BUGSExample' href='#JuliaBUGS.BUGSExamples.BUGSExample'><span class="jlbinding">JuliaBUGS.BUGSExamples.BUGSExample</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
BUGSExample
```


A BUGS example: model code in multiple representations, data, inits, and optional reference results. Backed by a directory of plain files (`model.bugs`, `model.jl`, `model_fn.jl`, `data.json`, `results.json`, `meta.toml`) — see `BUGSExamples.path(ex, file)` to access the source files directly.

`BUGSExamples` itself has no JuliaBUGS dependency; consumers parse the model strings (or `include` `model.jl` / `model_fn.jl` with JuliaBUGS loaded) when they need a compiled model.

**Fields**
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
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/types.jl#L17-L49" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.ReferenceResults' href='#JuliaBUGS.BUGSExamples.ReferenceResults'><span class="jlbinding">JuliaBUGS.BUGSExamples.ReferenceResults</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
ReferenceResults
```


Reference posterior summaries for a BUGS example, plus provenance metadata.

`params` is a NamedTuple keyed by parameter name, each value a NamedTuple with at least `mean` and `std` fields (CI runs may also include `ess`, `rhat`). `meta` describes where the numbers came from — typically either `source = "reference"` (literature values) or `source = "ci"` (resampled by the BUGSExamples results workflow).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/types.jl#L1-L11" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Functions {#Functions}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.examples' href='#JuliaBUGS.BUGSExamples.examples'><span class="jlbinding">JuliaBUGS.BUGSExamples.examples</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
examples() -> NamedTuple
```


Return a flat NamedTuple of every available example, keyed by symbol.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/BUGSExamples.jl#L68-L72" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.list' href='#JuliaBUGS.BUGSExamples.list'><span class="jlbinding">JuliaBUGS.BUGSExamples.list</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
list([io::IO = stdout])
```


Print every available example grouped by volume.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/BUGSExamples.jl#L75-L79" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.path' href='#JuliaBUGS.BUGSExamples.path'><span class="jlbinding">JuliaBUGS.BUGSExamples.path</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
path(ex::BUGSExample, file::AbstractString) -> String
```


Absolute path to a source file inside the example&#39;s directory. Use this when consumers (JuliaBUGS tests, benchmarks, doc templates) need to `include` or read the source files directly:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats
model_expr = include(BUGSExamples.path(ex, "model.jl"))  # returns an Expr
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/types.jl#L71-L83" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples.load_example' href='#JuliaBUGS.BUGSExamples.load_example'><span class="jlbinding">JuliaBUGS.BUGSExamples.load_example</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
load_example(dir::String) -> BUGSExample
```


Construct a `BUGSExample` from a directory containing (at minimum) `meta.toml`, `data.json`, `model.bugs`, and `model.jl`. Optional files (`model_fn.jl`, `model.stan`, `model.py`, `reference.json`, `results.json`) are picked up when present.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/data_loader.jl#L100-L107" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Module {#Module}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.BUGSExamples' href='#JuliaBUGS.BUGSExamples'><span class="jlbinding">JuliaBUGS.BUGSExamples</span></a> <Badge type="info" class="jlObjectType jlModule" text="Module" /></summary>



```julia
JuliaBUGS.BUGSExamples
```


Classical BUGS example models with multi-language representations: original BUGS syntax (`model.bugs`), JuliaBUGS `@bugs` macro form (`model.jl`), JuliaBUGS `@model` macro form (`model_fn.jl`), and optionally Stan (`model.stan`) and NumPyro (`model.py`).

Examples live under `Volume_<n>/<name>/`. Each model directory holds the syntax variants as plain files, plus `meta.toml`, `data.json`, and optionally `reference.json` (literature values) and `results.json` (CI-sampled).

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.rats

# Option 1: parse the raw BUGS string
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)

# Option 2: include the Julia model file (returns an Expr)
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/300c2cd7f822d896bd2215e9388bfceca36272bc/JuliaBUGS/src/BUGSExamples/BUGSExamples.jl#L1-L24" target="_blank" rel="noreferrer">source</a></Badge>

</details>

