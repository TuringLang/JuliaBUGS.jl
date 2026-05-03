using JSON

"""
    _dict_to_namedtuple(d::Dict) -> NamedTuple

Convert a Dict{String, Any} to a NamedTuple, converting nested arrays properly.
Handles BUGS-style dot-separated names via Julia's `var"name.subname"` syntax.
"""
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

"""
    load_example_data(filepath::String)

Load a JSON data file and return structured data for a BUGSExample.

Each JSON file should have keys: `"data"`, `"inits"`, and optionally
`"inits_alternative"` and `"reference_results"`.
"""
function load_example_data(filepath::String)
    raw = JSON.parsefile(filepath)
    data = _dict_to_namedtuple(raw["data"])
    inits = _dict_to_namedtuple(raw["inits"])
    inits_alt = haskey(raw, "inits_alternative") && raw["inits_alternative"] !== nothing ?
        _dict_to_namedtuple(raw["inits_alternative"]) : inits
    ref = haskey(raw, "reference_results") && raw["reference_results"] !== nothing ?
        _dict_to_namedtuple(raw["reference_results"]) : nothing
    return (; data, inits, inits_alternative=inits_alt, reference_results=ref)
end
