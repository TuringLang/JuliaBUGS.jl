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
struct OfConstant <: OfType
    function OfConstant()
        return error(
            "OfConstant is a type specification, not an instantiable object. Use of(Constant) to create the type.",
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
function of(::Type{Array}, dims...)
    # Default to Float64 for unspecified array types
    # Dims can be integers or symbols (for referencing constants)
    return OfArray{Float64,length(dims),dims}
end

function of(::Type{Array}, T::Type, dims...)
    # Dims can be integers or symbols (for referencing constants)
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

# Infer OfType from concrete values
function of(value::Real)
    return of(Real)
end

function of(value::AbstractArray{T,N}) where {T,N}
    return of(Array, T, size(value)...)
end

function of(value::NamedTuple{names}) where {names}
    of_types = map(of, values(value))
    return OfNamedTuple{names,Tuple{of_types...}}
end

# Support for passing OfType types through of()
of(T::Type{<:OfType}) = T

# Create a marker type for Constant
struct Constant end

# Create OfConstant
of(::Type{Constant}) = OfConstant

# Replace OfConstants in a type with concrete values
function of(::Type{T}, pairs::Pair{Symbol}...) where {T<:OfType}
    return of(T, NamedTuple(pairs))
end

function of(::Type{T}; kwargs...) where {T<:OfType}
    return of(T, NamedTuple(kwargs))
end

function of(::Type{OfNamedTuple{Names,Types}}, replacements::NamedTuple) where {Names,Types}
    # Replace OfConstants and symbolic dimensions with concrete values
    new_types = ntuple(length(Names)) do i
        name = Names[i]
        field_type = Types.parameters[i]

        if field_type <: OfConstant && haskey(replacements, name)
            # Skip - constants are removed in the concrete type
            return nothing
        elseif field_type <: OfArray
            # Check if array has symbolic dimensions
            dims = get_dims(field_type)
            new_dims = map(dims) do d
                if d isa Symbol && haskey(replacements, d)
                    replacements[d]
                else
                    d
                end
            end
            if new_dims != dims
                # Create new array type with concrete dimensions
                T = get_element_type(field_type)
                return of(Array, T, new_dims...)
            else
                return field_type
            end
        elseif field_type <: OfNamedTuple
            # Recursively handle nested named tuples
            return of(field_type, replacements)
        else
            return field_type
        end
    end

    # Filter out the nothings (removed constants)
    filtered_names = Symbol[]
    filtered_types = DataType[]
    for (i, new_type) in enumerate(new_types)
        if !isnothing(new_type)
            push!(filtered_names, Names[i])
            push!(filtered_types, new_type)
        end
    end

    return OfNamedTuple{Tuple(filtered_names),Tuple{filtered_types...}}
end

function of(::Type{OfArray{T,N,D}}, replacements::NamedTuple) where {T,N,D}
    # Replace symbolic dimensions in array types
    new_dims = map(D) do d
        if d isa Symbol && haskey(replacements, d)
            replacements[d]
        else
            d
        end
    end
    return OfArray{T,N,new_dims}
end

function of(::Type{T}, replacements::NamedTuple) where {T<:OfType}
    # For other types (OfReal, OfConstant), just return as-is
    return T
end

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

function julia_type(::Type{OfConstant})
    return Real  # Constants can be any Real type (Int, Float64, etc.)
end

# rand implementations for types
function Base.rand(::Type{OfArray{T,N,D}}) where {T,N,D}
    if any(d -> d isa Symbol, D)
        error(
            "Cannot generate random array with symbolic dimensions. Use rand(T; kwargs...) with dimension values.",
        )
    end
    return rand(T, D...)
end

function Base.rand(::Type{OfReal{L,U}}) where {L,U}
    val = rand()
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && !isnothing(upper)
        return lower + val * (upper - lower)
    elseif !isnothing(lower)
        # For lower bound only, generate values in [lower, ∞)
        # Using exponential distribution shifted by lower
        return lower + randexp()
    elseif !isnothing(upper)
        # For upper bound only, generate values in (-∞, upper]
        # Using negative exponential distribution shifted by upper
        return upper - randexp()
    else
        return randn()  # Use normal distribution for unbounded
    end
end

function Base.rand(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(rand(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

# zero implementations for types
function Base.zero(::Type{OfArray{T,N,D}}) where {T,N,D}
    if any(d -> d isa Symbol, D)
        error(
            "Cannot create zero array with symbolic dimensions. Use zero(T; kwargs...) with dimension values.",
        )
    end
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
    dims_str = join(map(d -> d isa Symbol ? ":$d" : string(d), D), ", ")
    if T === Float64
        print(io, "of(Array, ", dims_str, ")")
    else
        print(io, "of(Array, ", T, ", ", dims_str, ")")
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

function Base.show(io::IO, ::Type{OfConstant})
    return print(io, "of(Constant)")
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
    value isa AbstractArray || error("Expected Array for OfArray, got $(typeof(value))")

    any(d -> d isa Symbol, D) && error(
        "Cannot validate array with symbolic dimensions. Use the parameterized constructor.",
    )

    # Check dimensions before conversion
    ndims(value) == N ||
        error("Array dimension mismatch: expected $N dimensions, got $(ndims(value))")
    size(value) == D || error("Array size mismatch: expected $D, got $(size(value))")

    arr = convert(Array{T,N}, value)
    return arr
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
    value isa NamedTuple ||
        error("Expected NamedTuple for OfNamedTuple, got $(typeof(value))")

    # Check that all required fields are present
    value_names = fieldnames(typeof(value))
    for name in Names
        if !(name in value_names)
            error("Missing required field: $name. Got fields: $(join(value_names, ", "))")
        end
    end

    vals = ntuple(length(Names)) do i
        field_name = Names[i]
        field_type = Types.parameters[i]
        field_type(getproperty(value, field_name))
    end
    return NamedTuple{Names}(vals)
end

function validate_leaf(::Type{OfConstant}, value)
    if value isa Real
        return value  # Keep the original type (Int, Float64, etc.)
    else
        error("Expected Real for OfConstant, got $(typeof(value))")
    end
end

# Check if a type is a leaf
is_leaf(::Type{<:OfArray}) = true
is_leaf(::Type{<:OfReal}) = true
is_leaf(::Type{<:OfNamedTuple}) = false
is_leaf(::Type{<:OfConstant}) = true

# Get size of OfType types
function Base.size(::Type{OfArray{T,N,D}}) where {T,N,D}
    if any(d -> d isa Symbol, D)
        error("Cannot get size of array with symbolic dimensions.")
    end
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

function Base.size(::Type{OfConstant})
    return ()  # Constants are scalars
end

# Get flattened length of OfType types
function Base.length(::Type{OfArray{T,N,D}}) where {T,N,D}
    if any(d -> d isa Symbol, D)
        error("Cannot get length of array with symbolic dimensions.")
    end
    return prod(D)
end

function Base.length(::Type{OfReal{L,U}}) where {L,U}
    return 1
end

function Base.length(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Sum lengths of all fields
    return sum(length(Types.parameters[i]) for i in 1:length(Names))
end

function Base.length(::Type{OfConstant})
    return 0  # Constants are not part of the flattened representation
end

# Check if a type has symbolic dimensions or constants
function has_symbolic_dims(::Type{T}) where {T<:OfType}
    if T <: OfArray
        dims = get_dims(T)
        return any(d -> d isa Symbol, dims)
    elseif T <: OfNamedTuple
        types = get_types(T)
        for i in 1:length(types.parameters)
            field_type = types.parameters[i]
            if field_type <: OfConstant || has_symbolic_dims(field_type)
                return true
            end
        end
        return false
    else
        return false
    end
end

# Get list of unresolved symbols in a type
function get_unresolved_symbols(::Type{T}) where {T<:OfType}
    symbols = Symbol[]

    function collect_symbols(oft_type::Type, path::String="")
        if oft_type <: OfArray
            dims = get_dims(oft_type)
            for d in dims
                if d isa Symbol
                    push!(symbols, d)
                end
            end
        elseif oft_type <: OfNamedTuple
            names = get_names(oft_type)
            types = get_types(oft_type)
            for (i, name) in enumerate(names)
                field_type = types.parameters[i]
                new_path = isempty(path) ? string(name) : "$path.$name"
                if field_type <: OfConstant
                    push!(symbols, name)
                else
                    collect_symbols(field_type, new_path)
                end
            end
        end
    end

    collect_symbols(T)
    return unique(symbols)
end

# Flatten implementation for types
function flatten(::Type{T}, values) where {T<:OfType}
    # Check for symbolic dimensions
    if has_symbolic_dims(T)
        error(
            "Cannot flatten type with symbolic dimensions or constants. Use of(T, rows=3, cols=4) to create a concrete type first.",
        )
    end

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
    # Check for symbolic dimensions
    if has_symbolic_dims(T)
        error(
            "Cannot unflatten type with symbolic dimensions or constants. Use of(T, rows=3, cols=4) to create a concrete type first.",
        )
    end

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

# Parameterized rand that accepts keyword arguments for constants
function Base.rand(::Type{T}; kwargs...) where {T<:OfType}
    concrete_type = of(T, NamedTuple(kwargs))
    if has_symbolic_dims(concrete_type)
        missing_symbols = get_unresolved_symbols(concrete_type)
        provided = keys(kwargs)
        error(
            "Missing values for symbolic dimensions: $(join(missing_symbols, ", ")). You provided: $(join(provided, ", "))",
        )
    end
    return rand(concrete_type)
end

# Parameterized zero that accepts keyword arguments for constants
function Base.zero(::Type{T}; kwargs...) where {T<:OfType}
    concrete_type = of(T, NamedTuple(kwargs))
    if has_symbolic_dims(concrete_type)
        missing_symbols = get_unresolved_symbols(concrete_type)
        provided = keys(kwargs)
        error(
            "Missing values for symbolic dimensions: $(join(missing_symbols, ", ")). You provided: $(join(provided, ", "))",
        )
    end
    return zero(concrete_type)
end

# Parameterized constructor that accepts keyword arguments for constants
function (::Type{T})(; kwargs...) where {T<:OfType}
    concrete_type = of(T, NamedTuple(kwargs))
    if has_symbolic_dims(concrete_type)
        missing_symbols = get_unresolved_symbols(concrete_type)
        provided = keys(kwargs)
        error(
            "Missing values for symbolic dimensions: $(join(missing_symbols, ", ")). You provided: $(join(provided, ", "))",
        )
    end
    return zero(concrete_type)
end
