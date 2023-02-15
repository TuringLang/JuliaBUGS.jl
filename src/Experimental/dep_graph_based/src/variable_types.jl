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

Var(name::Symbol) = Scalar(name)
Var(name::Symbol, index::Int) = ArrayElement(name, index)
function Var(name::Symbol, indices::Vector) 
    all(i -> i isa AbstractRange, indices) && return ArrayVariable(name, indices)
    any(i -> i isa AbstractRange, indices) && return ArraySlice(name, indices)
    return ArrayElement(name,  indices)
end

Base.Symbol(v::Scalar) = v.name
function Base.Symbol(v::ArrayVariable)
    return Symbol(v.name, "[", join([:(:) for i in 1:length(v.indices)], ", "), "]")
end
function Base.Symbol(v::Var)
    return Symbol(v.name, "[", join(v.indices, ", "), "]")
end

function Var(name::Symbol, array_map)
    if name in keys(array_map)
        return Var(name, [1:s for s in size(array_map[name])])
    else
        return Var(name)
    end
end

function hash(v::Var, h::UInt)
    return hash(v.name, hash(isscalar(v) ? false : v.indices, h))
end

function Base.:(==)(v1::Var, v2::Var)
    if typeof(v1) != typeof(v2)
        return false
    else
        return v1.name == v2.name && v1.indices == v2.indices
    end
end

Base.show(io::IO, v::Scalar) = print(io, v.name)
function Base.show(io::IO, v::ArrayVariable)
    print_indices = [:(:) for i in 1:length(v.indices)]
    print(io, v.name, "[", join(print_indices, ", "), "]")
end
function Base.show(io::IO, v::Var)
    print(io, v.name, "[", join(v.indices, ", "), "]")
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

# per Philipp's suggestion, can use https://github.com/scheinerman/Bijections.jl in the future
struct Vars
    var_id_map::Dict{Var, Int}
    id_var_map::Dict{Int, Var}
end
Vars() = Vars(Dict{Vars, Int}(), Dict{Int, Var}())

function Base.push!(vars::Vars, v::Var)
    if haskey(vars.var_id_map, v)
        return vars.var_id_map[v]
    else
        id = length(vars.var_id_map) + 1
        vars.var_id_map[v] = id
        vars.id_var_map[id] = v
        return id
    end
end

function Base.getindex(vars::Vars, v::Var)
    return vars.var_id_map[v]
end

function Base.show(io::IO, vars::Vars)
    # print without types
    print(io, "Vars(")
    for (i, v) in enumerate(vars.var_id_map)
        print(io, v.first, " => ", v.second)
        if i < length(vars.id_var_map)
            print(io, ", ")
        end
    end
    print(io, ")")
end