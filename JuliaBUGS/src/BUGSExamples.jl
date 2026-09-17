"""
    BUGSExamples

The classic BUGS examples, read from the `BUGSExamples/` directory at the root of the
repository, or from the artifact snapshot of that directory when JuliaBUGS is installed on
its own.

Each example is a folder holding `example.toml`, the original program as `model.bugs`,
and `data.json`, `inits.json`, `inits_alternative.json`, and `reference.json` where the
example has them. The folders are read when the package loads. `VOLUME_1`, `VOLUME_2`, and
`VOLUME_3` hold the examples of each volume as `NamedTuple`s, and every example is also
bound by its key, so `VOLUME_1.rats` and `rats` are the same [`Example`](@ref).

Examples marked `blocked` in `example.toml` use language features JuliaBUGS does not
support yet, and examples marked `lazy` are too large to read at load time. Neither is in
the `VOLUME_N` tuples; both can be read explicitly with [`load`](@ref) and are shown by
[`list`](@ref).
"""
module BUGSExamples

using Artifacts, LazyArtifacts, TOML
using JSON
using OrderedCollections: OrderedDict
using JuliaBUGS: JuliaBUGS

"""
    Example

One BUGS example. `model_def` is the parsed program, ready for `compile`, and
`original_syntax_program` is the program text it was parsed from. `data`, `inits`, and
`inits_alternative` are `NamedTuple`s, empty when the example has none. `reference_results`
is a `NamedTuple` of the summaries published with the example, or `nothing`. `path` is the
directory the example was read from.
"""
struct Example{DNT<:NamedTuple,INT<:NamedTuple,INT2<:NamedTuple,RNT}
    name::String
    model_def::Expr
    original_syntax_program::String
    data::DNT
    inits::INT
    inits_alternative::INT2
    reference_results::RNT
    path::String
end

struct Entry
    volume::Symbol
    key::Symbol
    name::String
    path::String
    blocked::Union{Nothing,String}
    lazy::Bool
end

const SIBLING = normpath(joinpath(@__DIR__, "..", "..", "BUGSExamples"))

function root()
    isdir(joinpath(SIBLING, "volume_1")) && return SIBLING
    return artifact"BUGSExamples"
end

# Recorded as a precompilation dependency so that editing an example file in a checkout
# rebuilds the cache.
function tracked(path::AbstractString)
    Base.include_dependency(path)
    return path
end

read_toml(path) = TOML.parsefile(tracked(path))
read_json(path) = JSON.parsefile(tracked(path); dicttype=OrderedDict{String,Any})

from_json(x::AbstractDict) =
    NamedTuple{Tuple(Symbol.(keys(x)))}(Tuple(from_json.(values(x))))
from_json(::Nothing) = missing
from_json(x) = x

# Nested arrays are rows, so `[[1, 2], [3, 4]]` is the matrix `[1 2; 3 4]`.
function from_json(x::AbstractVector)
    if !isempty(x) && all(e -> e isa AbstractVector, x)
        rows = map(from_json, x)
        allequal(map(size, rows)) || error("ragged array: $(map(size, rows))")
        return stack(rows; dims=1)
    end
    return map(from_json, x)
end

function read_optional(path)
    isfile(path) || return nothing
    return from_json(read_json(path))
end

"""
    load(dir::AbstractString)

Read the example stored in the directory `dir`.
"""
function load(dir::AbstractString)
    meta = read_toml(joinpath(dir, "example.toml"))
    program = read(tracked(joinpath(dir, "model.bugs")), String)
    model_def = JuliaBUGS.Parser._bugs_string_input(program, false)
    data = something(read_optional(joinpath(dir, "data.json")), NamedTuple())
    inits = something(read_optional(joinpath(dir, "inits.json")), NamedTuple())
    inits_alternative = something(
        read_optional(joinpath(dir, "inits_alternative.json")), NamedTuple()
    )
    reference_results = read_optional(joinpath(dir, "reference.json"))
    return Example(
        meta["name"],
        model_def,
        program,
        data,
        inits,
        inits_alternative,
        reference_results,
        String(dir),
    )
end

function entries(root::AbstractString)
    out = Entry[]
    for volume in filter(startswith("volume_"), readdir(tracked(root)))
        volume_dir = tracked(joinpath(root, volume))
        for key in readdir(volume_dir)
            dir = joinpath(volume_dir, key)
            isdir(dir) || continue
            meta = read_toml(joinpath(dir, "example.toml"))
            push!(
                out,
                Entry(
                    Symbol(volume),
                    Symbol(key),
                    meta["name"],
                    dir,
                    get(meta, "blocked", nothing),
                    get(meta, "lazy", false),
                ),
            )
        end
    end
    return out
end

const ENTRIES = entries(root())

function entry(volume::Symbol, key::Symbol)
    i = findfirst(e -> e.volume === volume && e.key === key, ENTRIES)
    i === nothing && error("no example $key in $volume")
    return ENTRIES[i]
end

function entry(key::Symbol)
    found = filter(e -> e.key === key, ENTRIES)
    isempty(found) && error("no example $key")
    length(found) > 1 &&
        error("$key is in more than one volume: $(map(e -> e.volume, found))")
    return only(found)
end

"""
    load(key::Symbol)
    load(volume::Symbol, key::Symbol)

Read an example by key, including the blocked and lazy ones that `VOLUME_N` leave out.
"""
load(key::Symbol) = load(entry(key).path)
load(volume::Symbol, key::Symbol) = load(entry(volume, key).path)

const VOLUMES = let groups = OrderedDict{Symbol,Vector{Pair{Symbol,Example}}}()
    for e in ENTRIES
        (e.blocked === nothing && !e.lazy) || continue
        push!(get!(groups, e.volume, Pair{Symbol,Example}[]), e.key => load(e.path))
    end
    NamedTuple{Tuple(keys(groups))}(Tuple((; group...) for group in values(groups)))
end

for (volume, examples) in pairs(VOLUMES)
    @eval const $(Symbol(uppercase(string(volume)))) = $examples
    for (key, example) in pairs(examples)
        @eval const $key = $example
    end
end

"""
    volumes()

The examples that load with the package, as a `NamedTuple` of `NamedTuple`s keyed by
volume: `volumes().volume_1` is `VOLUME_1`.
"""
volumes() = VOLUMES

"""
    list([io::IO=stdout])

Print every example on disk, grouped by volume, marking the blocked and lazy ones.
"""
function list(io::IO=stdout)
    for volume in unique(e.volume for e in ENTRIES)
        println(io, replace(titlecase(string(volume)), "_" => " "))
        for e in filter(e -> e.volume === volume, ENTRIES)
            note = if e.blocked !== nothing
                "  [blocked: $(e.blocked)]"
            elseif e.lazy
                "  [load on demand]"
            else
                ""
            end
            println(io, "  ", rpad(e.key, 26), e.name, note)
        end
    end
    return nothing
end

end
