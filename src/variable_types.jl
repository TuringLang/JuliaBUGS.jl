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
function Var(name::Symbol, indices::NTuple)
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

Base.Symbol(v::Scalar) = v.name
function Base.Symbol(v::Var)
    return Symbol(v.name, "[", join(v.indices, ", "), "]")
end

function hash(v::Var, h::UInt)
    return hash(v.name, hash(isscalar(v) ? false : v.indices, h))
end

function Base.:(==)(v1::Var, v2::Var)
    typeof(v1) != typeof(v2) && return false
    return v1.name == v2.name && v1.indices == v2.indices
end

Base.show(io::IO, v::Scalar) = print(io, v.name)
function Base.show(io::IO, v::Var)
    return print(io, v.name, "[", join(v.indices, ", "), "]")
end

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

function eval(v::Var, env::Dict)
    !haskey(env, v.name) && return nothing
    v isa Scalar && return env[v.name]
    
    value = env[v.name][v.indices...]
    any(ismissing, value) && return nothing
    return value
end

function varname(v::Scalar)
    lens = AbstractPPL.IdentityLens()
    return AbstractPPL.VarName{v.name}(lens)
end
function varname(v::Var)
    lens = AbstractPPL.IndexLens(v.indices)
    return AbstractPPL.VarName{v.name}(lens)
end
