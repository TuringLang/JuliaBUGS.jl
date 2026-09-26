
# API Reference {#API-Reference}



## Types {#Types}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.BUGSExample' href='#BUGSExamples.BUGSExample'><span class="jlbinding">BUGSExamples.BUGSExample</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



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
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/types.jl#L17-L49" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.ReferenceResults' href='#BUGSExamples.ReferenceResults'><span class="jlbinding">BUGSExamples.ReferenceResults</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
ReferenceResults
```


Reference posterior summaries for a BUGS example, plus provenance metadata.

`params` is a NamedTuple keyed by parameter name, each value a NamedTuple with at least `mean` and `std` fields (CI runs may also include `ess`, `rhat`). `meta` describes where the numbers came from — typically either `source = "reference"` (literature values) or `source = "ci"` (resampled by the BUGSExamples results workflow).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/types.jl#L1-L11" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Functions {#Functions}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.list' href='#BUGSExamples.list'><span class="jlbinding">BUGSExamples.list</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
list([io::IO = stdout])
```


Print every available example grouped by volume.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/BUGSExamples.jl#L82-L86" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.examples' href='#BUGSExamples.examples'><span class="jlbinding">BUGSExamples.examples</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
examples() -> NamedTuple
```


Return a flat NamedTuple of every available example, keyed by symbol.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/BUGSExamples.jl#L75-L79" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.path' href='#BUGSExamples.path'><span class="jlbinding">BUGSExamples.path</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
path(ex::BUGSExample, file::AbstractString) -> String
```


Absolute path to a source file inside the example&#39;s directory. Use this when consumers (JuliaBUGS tests, benchmarks, doc templates) need to `include` or read the source files directly:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats
model_expr = include(BUGSExamples.path(ex, "model.jl"))  # returns an Expr
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/types.jl#L71-L83" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.load_example' href='#BUGSExamples.load_example'><span class="jlbinding">BUGSExamples.load_example</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
load_example(dir::String) -> BUGSExample
```


Construct a `BUGSExample` from a directory containing (at minimum) `meta.toml`, `data.json`, `model.bugs`, and `model.jl`. Optional files (`model_fn.jl`, `model.stan`, `model.py`, `reference.json`, `results.json`) are picked up when present.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/data_loader.jl#L95-L102" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Module {#Module}
<details class='jldocstring custom-block' open>
<summary><a id='BUGSExamples.BUGSExamples' href='#BUGSExamples.BUGSExamples'><span class="jlbinding">BUGSExamples.BUGSExamples</span></a> <Badge type="info" class="jlObjectType jlModule" text="Module" /></summary>



```julia
BUGSExamples
```


A standalone Julia package containing classical BUGS example models with multi-language representations: original BUGS syntax (`model.bugs`), JuliaBUGS `@bugs` macro form (`model.jl`), JuliaBUGS `@model` macro form (`model_fn.jl`), and optionally Stan (`model.stan`) and NumPyro (`model.py`).

**No JuliaBUGS dependency required.** Each model directory holds the syntax variants as plain files; this package reads them as strings at load time.

```julia
using BUGSExamples

BUGSExamples.list()                        # browse available models
ex = BUGSExamples.rats                     # access by symbol
println(ex.original_syntax_program)        # raw BUGS source
println(ex.data)                           # data as NamedTuple
BUGSExamples.path(ex, "model.jl")          # path to the @bugs Julia file
```


When compilation is needed, pass the model source to JuliaBUGS:

```julia
using JuliaBUGS, BUGSExamples
ex = BUGSExamples.rats

# Option 1: parse the raw BUGS string
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)

# Option 2: include the Julia model file (returns an Expr)
model_def = include(BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/4a8a67aa6c1502d91f01a5774a3b87b24e0aaae2/BUGSExamples/src/BUGSExamples.jl#L1-L35" target="_blank" rel="noreferrer">source</a></Badge>

</details>

