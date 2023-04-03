"""
    Var

A variable type that can be used to represent a scalar or an array element.
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
    indices::Tuple{N, Union{Int, UnitRange, Colon}}
end

isscalar(v::Var) = v isa Scalar || v isa ArrayElement

Base.size(::Scalar) = ()
Base.size(::ArrayElement) = ()
Base.size(v::ArrayVar) = Tuple(map(length, v.indices))

Var(name::Symbol) = Scalar(name, ())
Var(name::Symbol, index::Int) = ArrayElement(name, (index))
function Var(name::Symbol, indices::Vector)
    all(x -> x isa Number && isinteger(x), indices) && return ArrayElement(name, indices)
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
        scalarized_vars[i] = Var(v.name, collect(collected_indices[i]))
    end
    return scalarized_vars
end

# function eval(v::Var, env::Dict)
#     haskey(env, v.name) || return nothing
#     value = v isa Scalar ? env[v.name] : env[v.name][v.indices...]
#     ismissing(value) && return nothing
#     return value
# end

function VarName(v::Var)
    return eval(AbstractPPL.drop_escape(AbstractPPL.varname(Meta.parse(string(Symbol(v))))))
end
