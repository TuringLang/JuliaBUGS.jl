"""
    Var

A variable type that can be used to represent a scalar or an array element.
"""
abstract type Var end

struct Scalar <: Var
    name::Symbol
end

struct ArrayElement <: Var
    name::Symbol
    indices::Array
end

struct ArraySlice <: Var
    name::Symbol
    indices::Array
end

struct ArrayVariable <: Var
    name::Symbol
    indices::Array
end

isscalar(v::Var) = v isa Scalar || v isa ArrayElement

Base.size(::Scalar) = ()
Base.size(::ArrayElement) = ()
Base.size(v::ArraySlice) = Tuple(map(length, v.indices))

Var(name::Symbol) = Scalar(name)
Var(name::Symbol, index::Int) = ArrayElement(name, index)
function Var(name::Symbol, indices::Vector)
    all(x -> x isa Number && isinteger(x), indices) && return ArrayElement(name, indices)
    return ArraySlice(name, indices)
end

Base.Symbol(v::Scalar) = v.name
function Base.Symbol(v::ArrayVariable)
    return Symbol(v.name, "[", join([:(:) for i in 1:length(v.indices)], ", "), "]")
end
function Base.Symbol(v::Var)
    return Symbol(v.name, "[", join(v.indices, ", "), "]")
end

function hash(v::Var, h::UInt)
    return hash(v.name, hash(isscalar(v) ? false : v.indices, h))
end

function Base.:(==)(v1::ArraySlice, v2::ArrayVariable)
    return v1.name == v2.name && v1.indices == v2.indices
end
Base.:(==)(v1::ArrayVariable, v2::ArraySlice) = v2 == v1
function Base.:(==)(v1::Var, v2::Var)
    typeof(v1) != typeof(v2) && return false
    return v1.name == v2.name && v1.indices == v2.indices
end

Base.show(io::IO, v::Scalar) = print(io, v.name)
function Base.show(io::IO, v::ArrayVariable)
    print_indices = [:(:) for _ in 1:length(v.indices)]
    return print(io, v.name, "[", join(print_indices, ", "), "]")
end
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

function eval(v::Var, env::Dict)
    haskey(env, v.name) || return nothing
    if v isa Scalar
        return env[v.name]
    else
        return env[v.name][v.indices...]
    end
end

"""
    Vars

A bijection between variables and IDs.
"""
const Vars = Bijection{Var,Int}

function Base.push!(vars::Vars, v::Var)
    haskey(vars, v) && return nothing
    return vars[v] = length(vars) + 1
end

function Base.show(io::IO, vars::Vars)
    print(io, "Vars(")
    for (i, v) in enumerate(vars)
        print(io, v.first, " => ", v.second)
        i < length(vars) && print(io, ", ")
    end
    print(io, ")")
end
