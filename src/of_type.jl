# Abstract base type for all Of types
abstract type OfType end

# Parametric types that store specification in type parameters
# These are meant to be types only, not instantiable objects
struct OfReal{Lower,Upper} <: OfType
    function OfReal{L,U}() where {L,U}
        return error(
            "OfReal is a type specification, not an instantiable object. Use of(Real, ...) to create the type.",
        )
    end
end
struct OfArray{T,N,Dims} <: OfType
    function OfArray{T,N,D}() where {T,N,D}
        return error(
            "OfArray is a type specification, not an instantiable object. Use of(Array, ...) to create the type.",
        )
    end
end
struct OfNamedTuple{Names,Types<:Tuple} <: OfType
    function OfNamedTuple{Names,Types}() where {Names,Types}
        return error(
            "OfNamedTuple is a type specification, not an instantiable object. Use of(...) to create the type.",
        )
    end
end

# Helper functions to extract type parameters
get_lower(::Type{OfReal{L,U}}) where {L,U} = L
get_upper(::Type{OfReal{L,U}}) where {L,U} = U
get_element_type(::Type{OfArray{T,N,D}}) where {T,N,D} = T
get_ndims(::Type{OfArray{T,N,D}}) where {T,N,D} = N
get_dims(::Type{OfArray{T,N,D}}) where {T,N,D} = D
get_names(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Names
get_types(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Types

# Convert bounds to type parameters (using Val for runtime values)
bound_to_type(::Nothing) = Nothing
bound_to_type(x::Real) = Val{x}

# Extract value from Val type
type_to_bound(::Type{Nothing}) = nothing
type_to_bound(::Type{Val{x}}) where {x} = x

# Main of function that returns types
function of(::Type{Array}, dims::Int...)
    # Default to Float64 for unspecified array types
    return OfArray{Float64,length(dims),dims}
end

function of(::Type{Array}, T::Type, dims::Int...)
    return OfArray{T,length(dims),dims}
end

function of(::Type{Real})
    return OfReal{Nothing,Nothing}
end

function of(::Type{Real}, lower::Union{Real,Nothing}, upper::Union{Real,Nothing})
    L = bound_to_type(lower)
    U = bound_to_type(upper)
    return OfReal{L,U}
end

function of(nt::NamedTuple{names}) where {names}
    of_types = map(of, values(nt))
    return OfNamedTuple{names,Tuple{of_types...}}
end

# Support for passing OfType types through of()
of(T::Type{<:OfType}) = T

# Julia type extraction
function julia_type(::Type{OfArray{T,N,D}}) where {T,N,D}
    return Array{T,N}
end

function julia_type(::Type{OfReal{L,U}}) where {L,U}
    return Float64
end

function julia_type(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    jl_types = Tuple{[julia_type(T) for T in Types.parameters]...}
    return NamedTuple{Names,jl_types}
end

# rand implementations for types
function Base.rand(::Type{OfArray{T,N,D}}) where {T,N,D}
    return rand(T, D...)
end

function Base.rand(::Type{OfReal{L,U}}) where {L,U}
    val = rand()
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && !isnothing(upper)
        return lower + val * (upper - lower)
    elseif !isnothing(lower)
        return lower + val
    elseif !isnothing(upper)
        return upper * val
    else
        return val
    end
end

function Base.rand(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(rand(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

# zero implementations for types
function Base.zero(::Type{OfArray{T,N,D}}) where {T,N,D}
    return zeros(T, D...)
end

function Base.zero(::Type{OfReal{L,U}}) where {L,U}
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && lower > 0
        return lower
    elseif !isnothing(upper) && upper < 0
        return upper
    else
        return 0.0
    end
end

function Base.zero(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(zero(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

# Show implementations
function Base.show(io::IO, ::Type{OfArray{T,N,D}}) where {T,N,D}
    if T === Float64
        print(io, "of(Array, ", join(D, ", "), ")")
    else
        print(io, "of(Array, ", T, ", ", join(D, ", "), ")")
    end
end

function Base.show(io::IO, ::Type{OfReal{L,U}}) where {L,U}
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if isnothing(lower) && isnothing(upper)
        print(io, "of(Real)")
    else
        print(
            io,
            "of(Real, ",
            something(lower, "nothing"),
            ", ",
            something(upper, "nothing"),
            ")",
        )
    end
end

function Base.show(io::IO, ::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    print(io, "of((")
    for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
        print(io, name, "=", T)
        if i < length(Names)
            print(io, ", ")
        end
    end
    return print(io, "))")
end

# Make OfType types callable as constructors
function (::Type{T})(value) where {T<:OfType}
    if is_leaf(T)
        return validate_leaf(T, value)
    else
        return validate_container(T, value)
    end
end

function validate_leaf(::Type{OfArray{T,N,D}}, value) where {T,N,D}
    if value isa AbstractArray
        arr = convert(Array{T,N}, value)
        if size(arr) != D
            error("Array dimensions mismatch: expected $D, got $(size(arr))")
        end
        return arr
    else
        error("Expected Array for OfArray, got $(typeof(value))")
    end
end

function validate_leaf(::Type{OfReal{L,U}}, value) where {L,U}
    if value isa Real
        val = convert(Float64, value)
        lower = type_to_bound(L)
        upper = type_to_bound(U)

        if !isnothing(lower) && val < lower
            error("Value $val is below lower bound $lower")
        end
        if !isnothing(upper) && val > upper
            error("Value $val is above upper bound $upper")
        end
        return val
    else
        error("Expected Real for OfReal, got $(typeof(value))")
    end
end

function validate_container(::Type{OfNamedTuple{Names,Types}}, value) where {Names,Types}
    if value isa NamedTuple
        vals = ntuple(length(Names)) do i
            field_name = Names[i]
            field_type = Types.parameters[i]
            field_type(getproperty(value, field_name))
        end
        return NamedTuple{Names}(vals)
    else
        error("Expected NamedTuple for OfNamedTuple, got $(typeof(value))")
    end
end

# Check if a type is a leaf
is_leaf(::Type{<:OfArray}) = true
is_leaf(::Type{<:OfReal}) = true
is_leaf(::Type{<:OfNamedTuple}) = false

# Get size of OfType types
function Base.size(::Type{OfArray{T,N,D}}) where {T,N,D}
    return D
end

function Base.size(::Type{OfReal{L,U}}) where {L,U}
    return ()  # Scalar has empty dimensions
end

function Base.size(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Return a named tuple with dimensions of each field
    dims = map(Names) do name
        idx = findfirst(==(name), Names)
        size(Types.parameters[idx])
    end
    return NamedTuple{Names}(dims)
end

# Get flattened length of OfType types
function Base.length(::Type{OfArray{T,N,D}}) where {T,N,D}
    return prod(D)
end

function Base.length(::Type{OfReal{L,U}}) where {L,U}
    return 1
end

function Base.length(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Sum lengths of all fields
    return sum(length(Types.parameters[i]) for i in 1:length(Names))
end

# Flatten implementation for types
function flatten(::Type{T}, values) where {T<:OfType}
    # First validate the values match the specification
    validated = T(values)

    # Extract all numerical values in order
    numerical_values = Real[]

    function walk_tree(oft_type::Type, val_node)
        if is_leaf(oft_type)
            if oft_type <: OfArray
                append!(numerical_values, vec(val_node))
            elseif oft_type <: OfReal
                push!(numerical_values, val_node)
            end
        elseif oft_type <: OfNamedTuple
            names = get_names(oft_type)
            types = get_types(oft_type)
            for (i, name) in enumerate(names)
                walk_tree(types.parameters[i], getproperty(val_node, name))
            end
        end
    end

    walk_tree(T, validated)
    return numerical_values
end

# Unflatten implementation for types
function unflatten(::Type{T}, flat_values::Vector{<:Real}) where {T<:OfType}
    pos = Ref(1)

    function reconstruct_node(oft_type::Type)
        if is_leaf(oft_type)
            if oft_type <: OfArray
                dims = size(oft_type)
                n_elements = prod(dims)
                if pos[] + n_elements - 1 > length(flat_values)
                    error("Not enough values in flat array")
                end
                values = flat_values[pos[]:(pos[] + n_elements - 1)]
                pos[] += n_elements
                return reshape(values, dims)
            elseif oft_type <: OfReal
                if pos[] > length(flat_values)
                    error("Not enough values in flat array")
                end
                val = flat_values[pos[]]
                pos[] += 1

                # Apply bounds validation
                lower = type_to_bound(get_lower(oft_type))
                upper = type_to_bound(get_upper(oft_type))

                if !isnothing(lower) && val < lower
                    error("Value $val is below lower bound $lower")
                end
                if !isnothing(upper) && val > upper
                    error("Value $val is above upper bound $upper")
                end
                return val
            end
        elseif oft_type <: OfNamedTuple
            names = get_names(oft_type)
            types = get_types(oft_type)
            values = Tuple(reconstruct_node(types.parameters[i]) for i in 1:length(names))
            return NamedTuple{names}(values)
        end
    end

    reconstructed = reconstruct_node(T)

    if pos[] - 1 != length(flat_values)
        error("Unused values in flat array")
    end

    return reconstructed
end
