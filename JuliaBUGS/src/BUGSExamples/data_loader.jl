using JSON
using TOML

function _dict_to_namedtuple(d::AbstractDict)
    pairs = [Symbol(k) => _convert_value(v) for (k, v) in d]
    return NamedTuple(pairs)
end

function _convert_value(v)
    if v isa AbstractDict
        return _dict_to_namedtuple(v)
    elseif v isa AbstractVector
        if !isempty(v) && v[1] isa AbstractVector
            return _vectors_to_matrix(v)
        elseif !isempty(v) && v[1] isa AbstractDict
            return [_dict_to_namedtuple(x) for x in v]
        else
            return _typed_vector(v)
        end
    else
        return v
    end
end

function _vectors_to_matrix(vv::AbstractVector)
    nrows = length(vv)
    ncols = length(vv[1])
    all_vals = Iterators.flatten(vv)
    if all(x -> x isa Integer, all_vals)
        T = Int
    elseif all(x -> x isa Real, Iterators.flatten(vv))
        T = Float64
    else
        T = Any
    end
    mat = Matrix{T}(undef, nrows, ncols)
    for i in 1:nrows
        for j in 1:ncols
            mat[i, j] = vv[i][j]
        end
    end
    return mat
end

function _typed_vector(v::AbstractVector)
    if all(x -> x isa Integer, v)
        return convert(Vector{Int}, v)
    elseif all(x -> x isa Real, v)
        return convert(Vector{Float64}, v)
    else
        return v
    end
end

# Read a model-source file as a String, trimming trailing whitespace.
# Returns `""` if the file doesn't exist (i.e. the syntax variant is unavailable).
function _read_source(dir::String, file::String)
    p = joinpath(dir, file)
    return isfile(p) ? rstrip(read(p, String)) * "\n" : ""
end

function _load_meta(dir::String)
    meta_path = joinpath(dir, "meta.toml")
    isfile(meta_path) || error("Missing meta.toml in $dir")
    raw = TOML.parsefile(meta_path)
    name = get(raw, "name", basename(dir))
    description = get(raw, "description", "")
    # `String[…]` forces a Vector{String} even when TOML hands us an empty
    # `Vector{Union{}}` (which happens on Julia 1.11 for `citations = []`).
    citations = String[s for s in get(raw, "citations", String[])]
    doodlebugs_id = get(raw, "doodlebugs_id", nothing)
    volume = Int(get(raw, "volume", 0))
    order = Int(get(raw, "order", 999))
    tags = String[s for s in get(raw, "tags", String[])]
    return (; name, description, citations, doodlebugs_id, volume, order, tags)
end

function _load_data_inits(dir::String)
    data_path = joinpath(dir, "data.json")
    isfile(data_path) || error("Missing data.json in $dir")
    raw = JSON.parsefile(data_path)
    data = _dict_to_namedtuple(raw["data"])
    inits = _dict_to_namedtuple(raw["inits"])
    inits_alt = if haskey(raw, "inits_alternative") && raw["inits_alternative"] !== nothing
        _dict_to_namedtuple(raw["inits_alternative"])
    else
        inits
    end
    return (; data, inits, inits_alternative=inits_alt)
end

function _load_results_file(path::String)
    isfile(path) || return nothing
    raw = JSON.parsefile(path)
    params = _dict_to_namedtuple(raw["params"])
    meta = haskey(raw, "_meta") ? _dict_to_namedtuple(raw["_meta"]) : NamedTuple()
    return ReferenceResults(params, meta)
end

"""
    load_example(dir::String) -> BUGSExample

Construct a `BUGSExample` from a directory containing (at minimum) `meta.toml`,
`data.json`, `model.bugs`, and `model.jl`. Optional files (`model_fn.jl`,
`model.stan`, `model.py`, `reference.json`, `results.json`) are picked up when
present.
"""
function load_example(dir::String)
    meta = _load_meta(dir)
    di = _load_data_inits(dir)
    original_syntax_program = _read_source(dir, "model.bugs")
    model_def = _read_source(dir, "model.jl")
    model_function = _read_source(dir, "model_fn.jl")
    stan_code = _read_source(dir, "model.stan")
    numpyro_code = _read_source(dir, "model.py")
    reference_results = _load_results_file(joinpath(dir, "reference.json"))
    sampled_results = _load_results_file(joinpath(dir, "results.json"))
    return BUGSExample(
        meta.name,
        meta.description,
        meta.citations,
        meta.doodlebugs_id,
        meta.volume,
        meta.order,
        meta.tags,
        original_syntax_program,
        model_def,
        model_function,
        stan_code,
        numpyro_code,
        di.data,
        di.inits,
        di.inits_alternative,
        reference_results,
        sampled_results,
        abspath(dir),
    )
end
