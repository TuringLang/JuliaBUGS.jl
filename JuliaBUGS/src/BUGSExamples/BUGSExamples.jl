"""
    JuliaBUGS.BUGSExamples

Classical BUGS example models with multi-language representations: original
BUGS syntax (`model.bugs`), JuliaBUGS `@bugs` macro form (`model.jl`),
JuliaBUGS `@model` macro form (`model_fn.jl`), and optionally Stan
(`model.stan`) and NumPyro (`model.py`).

Examples live under `Volume_<n>/<name>/`. Each model directory holds the
syntax variants as plain files, plus `meta.toml`, `data.json`, and
optionally `reference.json` (literature values) and `results.json` (CI-sampled).

```julia
using JuliaBUGS
ex = JuliaBUGS.BUGSExamples.rats

# Option 1: parse the raw BUGS string
model = compile(@bugs(ex.original_syntax_program), ex.data, ex.inits)

# Option 2: include the Julia model file (returns an Expr)
model_def = include(JuliaBUGS.BUGSExamples.path(ex, "model.jl"))
model = compile(model_def, ex.data, ex.inits)
```
"""
module BUGSExamples

include("types.jl")
include("data_loader.jl")

export BUGSExample, ReferenceResults

const EXAMPLES_DIR = joinpath(@__DIR__)

# Discover every example dir under `Volume_<n>/<name>/` that has a meta.toml.
function _discover_examples()
    dirs = String[]
    for vol_entry in readdir(EXAMPLES_DIR; join=true)
        isdir(vol_entry) || continue
        startswith(basename(vol_entry), "Volume_") || continue
        for ex_entry in readdir(vol_entry; join=true)
            isdir(ex_entry) && isfile(joinpath(ex_entry, "meta.toml")) && push!(dirs, ex_entry)
        end
    end
    return dirs
end

const _ALL_EXAMPLES = let
    loaded = [(basename(dir), load_example(dir)) for dir in _discover_examples()]
    # Sort by (volume, order) so docs and `list()` show examples in WinBUGS sequence.
    sort!(loaded; by = ((_, ex),) -> (ex.volume, ex.order))
    NamedTuple(Symbol(name) => ex for (name, ex) in loaded)
end

# Bind each example as a top-level constant: JuliaBUGS.BUGSExamples.rats, …
for (name, ex) in pairs(_ALL_EXAMPLES)
    @eval const $(name) = $(ex)
end

const VOLUME_1 = NamedTuple(k => v for (k, v) in pairs(_ALL_EXAMPLES) if v.volume == 1)
const VOLUME_2 = NamedTuple(k => v for (k, v) in pairs(_ALL_EXAMPLES) if v.volume == 2)
const VOLUME_3 = NamedTuple(k => v for (k, v) in pairs(_ALL_EXAMPLES) if v.volume == 3)
const VOLUME_4 = NamedTuple(k => v for (k, v) in pairs(_ALL_EXAMPLES) if v.volume == 4)

export VOLUME_1, VOLUME_2, VOLUME_3, VOLUME_4

"""
    examples() -> NamedTuple

Return a flat NamedTuple of every available example, keyed by symbol.
"""
examples() = _ALL_EXAMPLES

"""
    list([io::IO = stdout])

Print every available example grouped by volume.
"""
function list(io::IO = stdout)
    println(io, "JuliaBUGS.BUGSExamples — Available Models")
    for (vol, vol_examples) in ((1, VOLUME_1), (2, VOLUME_2), (3, VOLUME_3), (4, VOLUME_4))
        isempty(vol_examples) && continue
        println(io, "\nVolume $vol ($(length(vol_examples)) examples):")
        for (name, ex) in pairs(vol_examples)
            println(io, "  :$name — $(ex.name)")
        end
    end
end

export list, examples, path

end # module BUGSExamples
