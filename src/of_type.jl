abstract type OfType end
abstract type OfLeaf <: OfType end
abstract type OfContainer <: OfType end

struct OfArray{T,N} <: OfLeaf
    element_type::Type
    dims::NTuple{N,Int}
end

struct OfReal <: OfLeaf
    lower::Union{Nothing,Real}
    upper::Union{Nothing,Real}
end

struct OfTuple{T<:Tuple} <: OfContainer
    types::T
end

struct OfNamedTuple{names,T<:Tuple} <: OfContainer
    types::T
end

struct OfVector{T} <: OfContainer
    element_type::OfType
    length::Union{Nothing,Int}
end

struct OfDict{K,V} <: OfContainer
    key_type::Type{K}
    value_type::OfType
    keys::Union{Nothing,Vector{K}}
end

function of(::Type{Array}, dims::Int...)
    return OfArray{Any,length(dims)}(Any, dims)
end

function of(::Type{Array}, T::Union{Type,OfType}, dims::Int...)
    element_type = T isa OfType ? julia_type(T) : T
    return OfArray{element_type,length(dims)}(element_type, dims)
end

function of(::Type{Real})
    return OfReal(nothing, nothing)
end

function of(::Type{Real}, lower::Real, upper::Real)
    return OfReal(lower, upper)
end

function of(t::Tuple)
    of_types = map(of, t)
    return OfTuple(of_types)
end

function of(nt::NamedTuple{names}) where {names}
    of_types = map(of, values(nt))
    return OfNamedTuple{names,typeof(of_types)}(of_types)
end

function of(
    ::Type{Vector}, element_type::Union{Type,OfType}, len::Union{Nothing,Int}=nothing
)
    et = element_type isa OfType ? element_type : of(element_type)
    return OfVector{typeof(et)}(et, len)
end

function of(
    ::Type{Dict},
    K::Type,
    value_type::Union{Type,OfType},
    keys::Union{Nothing,Vector}=nothing,
)
    vt = value_type isa OfType ? value_type : of(value_type)
    return OfDict{K,typeof(vt)}(K, vt, keys)
end

function of(x::OfType)
    return x
end

function of(T::Type)
    if T <: Real
        return OfReal(nothing, nothing)
    else
        error("Unsupported type for of: $T")
    end
end

function julia_type(::OfArray{T,N}) where {T,N}
    return Array{T,N}
end

function julia_type(::OfReal)
    return Float64
end

function julia_type(oft::OfTuple)
    return Tuple{map(julia_type, oft.types)...}
end

function julia_type(oft::OfNamedTuple{names}) where {names}
    return NamedTuple{names,Tuple{map(julia_type, oft.types)...}}
end

function julia_type(ofv::OfVector)
    return Vector{julia_type(ofv.element_type)}
end

function julia_type(ofd::OfDict{K}) where {K}
    return Dict{K,julia_type(ofd.value_type)}
end

Base.rand(ofa::OfArray{T,N}) where {T,N} = rand(T, ofa.dims...)

function Base.rand(ofr::OfReal)
    val = rand()
    if !isnothing(ofr.lower) && !isnothing(ofr.upper)
        return ofr.lower + val * (ofr.upper - ofr.lower)
    elseif !isnothing(ofr.lower)
        return ofr.lower + val
    elseif !isnothing(ofr.upper)
        return ofr.upper * val
    else
        return val
    end
end

function Base.rand(oft::OfTuple)
    return map(rand, oft.types)
end

function Base.rand(oft::OfNamedTuple{names}) where {names}
    values = map(rand, oft.types)
    return NamedTuple{names}(values)
end

function Base.rand(ofv::OfVector)
    len = something(ofv.length, rand(1:10))  # default random length if not specified
    return [rand(ofv.element_type) for _ in 1:len]
end

function Base.rand(ofd::OfDict)
    if isnothing(ofd.keys)
        # Generate random keys if not specified
        n = rand(1:5)
        if ofd.key_type === Symbol
            ks = [Symbol("key_", i) for i in 1:n]
        elseif ofd.key_type === String
            ks = ["key_$i" for i in 1:n]
        elseif ofd.key_type <: Integer
            ks = collect(1:n)
        else
            error("Unsupported key type for random generation: $(ofd.key_type)")
        end
    else
        ks = ofd.keys
    end
    return Dict(k => rand(ofd.value_type) for k in ks)
end

Base.zero(ofa::OfArray{T,N}) where {T,N} = zeros(T, ofa.dims...)

function Base.zero(ofr::OfReal)
    if !isnothing(ofr.lower) && ofr.lower > 0
        return ofr.lower
    elseif !isnothing(ofr.upper) && ofr.upper < 0
        return ofr.upper
    else
        return 0.0
    end
end

function Base.zero(oft::OfTuple)
    return map(zero, oft.types)
end

function Base.zero(oft::OfNamedTuple{names}) where {names}
    values = map(zero, oft.types)
    return NamedTuple{names}(values)
end

function Base.zero(ofv::OfVector)
    len = something(ofv.length, 0)  # default to empty vector if length not specified
    return [zero(ofv.element_type) for _ in 1:len]
end

function Base.zero(ofd::OfDict{K}) where {K}
    if isnothing(ofd.keys)
        return Dict{K,julia_type(ofd.value_type)}()
    else
        return Dict(k => zero(ofd.value_type) for k in ofd.keys)
    end
end

(ofa::OfArray)() = zero(ofa)
(ofr::OfReal)() = zero(ofr)
(oft::OfTuple)() = zero(oft)
(ofnt::OfNamedTuple)() = zero(ofnt)
(ofv::OfVector)() = zero(ofv)
(ofd::OfDict)() = zero(ofd)

Base.convert(::Type{Type}, of_type::OfType) = julia_type(of_type)

function Base.show(io::IO, ofa::OfArray{T,N}) where {T,N}
    if T === Any
        print(io, "of(Array, ", join(ofa.dims, ", "), ")")
    else
        print(io, "of(Array, ", T, ", ", join(ofa.dims, ", "), ")")
    end
end

function Base.show(io::IO, ofr::OfReal)
    if isnothing(ofr.lower) && isnothing(ofr.upper)
        print(io, "of(Real)")
    else
        print(
            io,
            "of(Real, ",
            something(ofr.lower, "-∞"),
            ", ",
            something(ofr.upper, "∞"),
            ")",
        )
    end
end

function Base.show(io::IO, oft::OfTuple)
    print(io, "of((")
    for (i, t) in enumerate(oft.types)
        print(io, t)
        if i < length(oft.types)
            print(io, ", ")
        end
    end
    return print(io, "))")
end

function Base.show(io::IO, ofnt::OfNamedTuple{names}) where {names}
    print(io, "of((")
    for (i, (name, t)) in enumerate(zip(names, ofnt.types))
        print(io, name, "=", t)
        if i < length(names)
            print(io, ", ")
        end
    end
    return print(io, "))")
end

function Base.show(io::IO, ofv::OfVector)
    if isnothing(ofv.length)
        print(io, "of(Vector, ", ofv.element_type, ")")
    else
        print(io, "of(Vector, ", ofv.element_type, ", ", ofv.length, ")")
    end
end

function Base.show(io::IO, ofd::OfDict{K}) where {K}
    if isnothing(ofd.keys)
        print(io, "of(Dict, ", K, ", ", ofd.value_type, ")")
    else
        print(io, "of(Dict, ", K, ", ", ofd.value_type, ", ", ofd.keys, ")")
    end
end

# Pytree-like traversal utilities

"""
    is_leaf(of_type)

Check if an OfType is a leaf node (not a container).
"""
is_leaf(::OfLeaf) = true
is_leaf(::OfContainer) = false

"""
    tree_map(f, of_type)

Apply function `f` to all leaf nodes in the tree structure.
"""
function tree_map(f, oft::OfType)
    if is_leaf(oft)
        return f(oft)
    elseif oft isa OfTuple
        return OfTuple(map(x -> tree_map(f, x), oft.types))
    elseif oft isa OfNamedTuple{names} where {names}
        new_types = map(x -> tree_map(f, x), oft.types)
        return OfNamedTuple{names,typeof(new_types)}(new_types)
    elseif oft isa OfVector
        return OfVector(tree_map(f, oft.element_type), oft.length)
    elseif oft isa OfDict{K} where {K}
        return OfDict{K,typeof(tree_map(f, oft.value_type))}(
            oft.key_type, tree_map(f, oft.value_type), oft.keys
        )
    else
        error("Unknown OfType: $(typeof(oft))")
    end
end

"""
    tree_leaves(of_type)

Collect all leaf nodes from the tree structure.
"""
function tree_leaves(oft::OfType)
    leaves = OfType[]
    function collect_leaves(node)
        if is_leaf(node)
            push!(leaves, node)
        elseif node isa OfTuple
            foreach(collect_leaves, node.types)
        elseif node isa OfNamedTuple
            foreach(collect_leaves, node.types)
        elseif node isa OfVector
            collect_leaves(node.element_type)
        elseif node isa OfDict
            collect_leaves(node.value_type)
        end
    end
    collect_leaves(oft)
    return leaves
end

"""
    tree_structure(of_type)

Return the structure of the tree without the leaf values.
"""
function tree_structure(oft::OfType)
    if is_leaf(oft)
        return nothing
    elseif oft isa OfTuple
        return (map(tree_structure, oft.types)...,)
    elseif oft isa OfNamedTuple{names} where {names}
        return NamedTuple{names}(map(tree_structure, oft.types))
    elseif oft isa OfVector
        return (Vector, tree_structure(oft.element_type), oft.length)
    elseif oft isa OfDict{K} where {K}
        return (Dict, K, tree_structure(oft.value_type), oft.keys)
    end
end

"""
    flatten(of_type)

Flatten the tree structure into a vector of leaves and return the structure.
"""
function flatten(oft::OfType)
    return tree_leaves(oft), tree_structure(oft)
end

"""
    unflatten(leaves, structure)

Reconstruct an OfType tree from leaves and structure.
"""
function unflatten(leaves::Vector{<:OfType}, structure)
    idx = Ref(1)
    function reconstruct(s)
        if isnothing(s)
            leaf = leaves[idx[]]
            idx[] += 1
            return leaf
        elseif s isa Tuple && length(s) > 0 && s[1] === Vector
            # OfVector case
            _, elem_struct, len = s
            elem_type = reconstruct(elem_struct)
            return OfVector(elem_type, len)
        elseif s isa Tuple && length(s) > 0 && s[1] === Dict
            # OfDict case
            _, K, val_struct, keys = s
            val_type = reconstruct(val_struct)
            return OfDict{K,typeof(val_type)}(K, val_type, keys)
        elseif s isa Tuple
            # OfTuple case
            types = map(reconstruct, s)
            return OfTuple(types)
        elseif s isa NamedTuple{names} where {names}
            # OfNamedTuple case
            types = map(reconstruct, values(s))
            return OfNamedTuple{names,typeof(types)}(types)
        else
            error("Unknown structure: $s")
        end
    end
    return reconstruct(structure)
end

"""
    tree_map_with_path(f, of_type)

Apply function `f(path, leaf)` to all leaf nodes, where path is a tuple of keys/indices.
"""
function tree_map_with_path(f, oft::OfType, path=())
    if is_leaf(oft)
        return f(path, oft)
    elseif oft isa OfTuple
        new_types = ntuple(
            i -> tree_map_with_path(f, oft.types[i], (path..., i)), length(oft.types)
        )
        return OfTuple(new_types)
    elseif oft isa OfNamedTuple{names} where {names}
        new_types = map(enumerate(names)) do (i, name)
            tree_map_with_path(f, oft.types[i], (path..., name))
        end
        return OfNamedTuple{names,typeof(new_types)}(new_types)
    elseif oft isa OfVector
        new_elem = tree_map_with_path(f, oft.element_type, (path..., :element))
        return OfVector(new_elem, oft.length)
    elseif oft isa OfDict{K} where {K}
        new_val = tree_map_with_path(f, oft.value_type, (path..., :value))
        return OfDict{K,typeof(new_val)}(oft.key_type, new_val, oft.keys)
    end
end
