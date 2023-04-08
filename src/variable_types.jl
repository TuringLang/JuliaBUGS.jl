"""
    Var

A lightweight type for representing variables in a model.
"""
abstract type Var end

struct Scalar <: Var
    name::Symbol
    indices::Tuple{}
end

struct ArrayElement{N} <: Var
    name::Symbol
    indices::NTuple{N, Int}
end

struct ArrayVar{N} <: Var
    name::Symbol
    indices::NTuple{N, Union{Int, UnitRange, Colon}}
end

Var(name::Symbol) = Scalar(name, ())
function Var(name::Symbol, indices)
    indices = map(indices) do i
        if i isa AbstractFloat
            isinteger(i) && return Int(i)
            error("Indices must be integers.")
        end
        return i
    end
    all(x -> x isa Integer, indices) && return ArrayElement(name, indices)
    return ArrayVar(name, indices)
end

Base.size(::Scalar) = ()
Base.size(::ArrayElement) = ()
function Base.size(v::ArrayVar)
    if any(x -> x isa Colon, v.indices)
        error("Can't get size of an array with colon indices.")
    end
    return Tuple(map(length, v.indices))
end

Base.Symbol(v::Scalar) = v.name
function Base.Symbol(v::Var)
    return Symbol(v.name, "[", join(v.indices, ", "), "]")
end

function hash(v::Var, h::UInt)
    return hash(v.name, hash(v.indices, h))
end

function Base.:(==)(v1::Var, v2::Var)
    typeof(v1) != typeof(v2) && return false
    return v1.name == v2.name && v1.indices == v2.indices
end

Base.show(io::IO, v::Scalar) = print(io, v.name)
function Base.show(io::IO, v::Var)
    return print(io, v.name, "[", join(v.indices, ", "), "]")
end

"""
    scalarize(v::Var)

Return an array of `Var`s that are scalarized from `v`. If `v` is a scalar, return an array of length 1 containing `v`.
All indices of `v` must be integer or UnitRange.

# Examples
```jldoctest
julia> scalarize(Var(:x, (1, 2:3)))
2-element Vector{JuliaBUGS.Var}:
 x[1, 2]
 x[1, 3]
```
"""
scalarize(v::Scalar) = [v]
scalarize(v::ArrayElement) = [v]
function scalarize(v::Var)
    collected_indices = collect(Iterators.product(v.indices...))
    scalarized_vars = Array{Var}(undef, size(collected_indices)...)
    for i in eachindex(collected_indices)
        scalarized_vars[i] = Var(v.name, collected_indices[i])
    end
    return scalarized_vars
end

"""
    evaluate(v::Var, env::Dict)

Evaluate `v` in the environment `env`. If `v` is a scalar, return the value of `v` in `env`. If `v` is an array, 
return an array of the same size as `v` with the values of `v` in `env` and `Var`s for the missing values. If `v` 
represent a multi-dimensional array, the return value is always scalarized, even when no array elements are data.

# Examples
```jldoctest
julia> eval(Var(:x, (1:2, )), Dict(:x => [1, missing]))
2-element Vector{Any}:
 1
  x[2]
```
"""
function evaluate(v::Var, env::Dict)
    haskey(env, v.name) || return v
    v isa Scalar && return env[v.name]
    if v isa ArrayElement
        value = env[v.name][v.indices...]
        return ismissing(value) ? v : value
    end
    value = map(x -> eval_var(x, env), scalarize(v))
    return reshape(value, size(v))
end

function varname(v::Scalar)
    lens = AbstractPPL.IdentityLens()
    return AbstractPPL.VarName{v.name}(lens)
end
function varname(v::Var)
    lens = AbstractPPL.IndexLens(v.indices)
    return AbstractPPL.VarName{v.name}(lens)
end
