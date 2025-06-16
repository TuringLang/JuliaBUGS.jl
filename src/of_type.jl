using Functors

abstract type OfType end

struct OfArray{T,N} <: OfType
    element_type::Type
    dims::NTuple{N,Int}
end

struct OfReal <: OfType
    lower::Union{Nothing,Real}
    upper::Union{Nothing,Real}
end

struct OfNamedTuple{names,T<:Tuple} <: OfType
    types::T
end

get_names(::OfNamedTuple{names}) where {names} = names

function of(::Type{Array}, dims::Int...)
    # Default to Float64 for unspecified array types
    return OfArray{Float64,length(dims)}(Float64, dims)
end

function of(::Type{Array}, T::Union{Type,OfType}, dims::Int...)
    element_type = T isa OfType ? julia_type(T) : T
    return OfArray{element_type,length(dims)}(element_type, dims)
end

function of(::Type{Real})
    return OfReal(nothing, nothing)
end

function of(::Type{Real}, lower::Union{Real,Nothing}, upper::Union{Real,Nothing})
    return OfReal(lower, upper)
end

function of(nt::NamedTuple{names}) where {names}
    of_types = map(of, values(nt))
    return OfNamedTuple{names,typeof(of_types)}(of_types)
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

function julia_type(oft::OfNamedTuple{names}) where {names}
    return NamedTuple{names,Tuple{map(julia_type, oft.types)...}}
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

function Base.rand(oft::OfNamedTuple{names}) where {names}
    values = map(rand, oft.types)
    return NamedTuple{names}(values)
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

function Base.zero(oft::OfNamedTuple{names}) where {names}
    values = map(zero, oft.types)
    return NamedTuple{names}(values)
end

(ofa::OfArray)() = zero(ofa)
(ofr::OfReal)() = zero(ofr)
(ofnt::OfNamedTuple)() = zero(ofnt)

Base.convert(::Type{Type}, of_type::OfType) = julia_type(of_type)

# Since OfType cannot be a subtype of Type, we need macros to transform the syntax
# The existing TypeOf wrapper approach is the right solution

# Type wrapper that preserves of specification while being usable in type annotations
struct TypeOf{T,S}
    spec::S

    TypeOf(spec::OfType) = new{julia_type(spec),typeof(spec)}(spec)
end

# Extract the Julia type from TypeOf
Base.eltype(::Type{TypeOf{T,S}}) where {T,S} = T

# Allow pattern matching on TypeOf
# Note: This would need special handling in the macro system
# For now, just provide a way to extract the type
julia_type(::TypeOf{T,S}) where {T,S} = T

# Macro for creating types from of specifications
macro of(expr)
    # Check if it's a tuple expression (for named tuple support)
    if Meta.isexpr(expr, :tuple) && length(expr.args) > 0
        # Check if all elements are assignments (named tuple pattern)
        all_assignments = all(arg -> Meta.isexpr(arg, :(=)), expr.args)

        if all_assignments
            # This is a named tuple like (a=..., b=...)
            field_names = Symbol[]
            field_types = []

            for field in expr.args
                if Meta.isexpr(field, :(=)) && length(field.args) == 2
                    name = field.args[1]
                    value_expr = field.args[2]

                    # Handle of() expressions
                    if Meta.isexpr(value_expr, :call) && value_expr.args[1] == :of
                        # Create the of specification and extract its Julia type
                        of_spec = esc(value_expr)
                        push!(field_types, :($julia_type($of_spec)))
                    else
                        # For non-of expressions, just use them directly
                        push!(field_types, esc(value_expr))
                    end
                    push!(field_names, name)
                else
                    error("Invalid field in named tuple: $field")
                end
            end

            # Return the NamedTuple type
            return :(NamedTuple{$(Tuple(field_names)),Tuple{$(field_types...)}})
        else
            # Check for parameters syntax (;a=..., b=...)
            if Meta.isexpr(expr.args[1], :parameters)
                # This is the (;a=..., b=...) syntax
                fields = expr.args[1].args
                field_names = Symbol[]
                field_types = []

                for field in fields
                    if Meta.isexpr(field, :(=)) && length(field.args) == 2
                        name = field.args[1]
                        value_expr = field.args[2]

                        # Handle of() expressions
                        if Meta.isexpr(value_expr, :call) && value_expr.args[1] == :of
                            # Create the of specification and extract its Julia type
                            of_spec = esc(value_expr)
                            push!(field_types, :($julia_type($of_spec)))
                        else
                            # For non-of expressions, just use them directly
                            push!(field_types, esc(value_expr))
                        end
                        push!(field_names, name)
                    else
                        error("Invalid field in named tuple: $field")
                    end
                end

                # Return the NamedTuple type
                return :(NamedTuple{$(Tuple(field_names)),Tuple{$(field_types...)}})
            else
                # Regular tuple, not supported for now
                error("@of with regular tuples is not supported. Use named tuples instead.")
            end
        end
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :of
        # Regular of(...) call
        return :(TypeOf(of($(map(esc, expr.args[2:end])...))))
    else
        return :(TypeOf(of($(esc(expr)))))
    end
end

# Functors.jl integration
# Leaf types should not be traversed
Functors.@leaf OfArray
Functors.@leaf OfReal

# Define functor for OfNamedTuple to enable traversal
function Functors.functor(::Type{<:OfNamedTuple{names}}, x) where {names}
    return NamedTuple{names}(x.types),
    nt -> OfNamedTuple{names,typeof(values(nt))}(values(nt))
end

function Base.show(io::IO, ofa::OfArray{T,N}) where {T,N}
    if T === Float64
        # For default Float64, show shorter form
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

function Base.show(io::IO, ofnt::OfNamedTuple{names}) where {names}
    print(io, "of((")
    name_tuple = names
    for (i, (name, t)) in enumerate(zip(name_tuple, ofnt.types))
        print(io, name, "=", t)
        if i < length(name_tuple)
            print(io, ", ")
        end
    end
    return print(io, "))")
end

# Functors.jl-based traversal utilities

"""
    is_leaf(of_type)

Check if an OfType is a leaf node (not a container).
"""
is_leaf(oft::OfType) = Functors.isleaf(oft)

"""
    tree_map(f, of_type)

Apply function `f` to all leaf nodes in the tree structure.
Uses Functors.jl's fmap for traversal.
"""
function tree_map(f, oft::OfType)
    return Functors.fmap(oft; exclude=is_leaf) do x
        f(x)
    end
end

"""
    flatten(of_type, values)

Flatten a structured value into a vector of numerical values according to the of_type specification.
Returns a vector of numbers that can be used for optimization.
"""
function flatten(oft::OfType, values)
    # First validate the values match the specification
    validated = validate(oft, values)

    # Extract all numerical values in order
    numerical_values = Real[]

    # Helper function to walk the tree
    function walk_tree(oft_node, val_node)
        if is_leaf(oft_node)
            if oft_node isa OfArray
                append!(numerical_values, vec(val_node))
            elseif oft_node isa OfReal
                push!(numerical_values, val_node)
            end
        elseif oft_node isa OfNamedTuple
            # Process fields in order
            for (i, name) in enumerate(get_names(oft_node))
                walk_tree(oft_node.types[i], getproperty(val_node, name))
            end
        end
    end

    walk_tree(oft, validated)
    return numerical_values
end

"""
    unflatten(of_type, flat_values)

Reconstruct a structured value from a flat vector of numerical values according to the of_type specification.
"""
function unflatten(oft::OfType, flat_values::Vector{<:Real})
    # Keep track of position in flat array
    pos = Ref(1)

    # Helper function to reconstruct from flat array
    function reconstruct_node(oft_node)
        if is_leaf(oft_node)
            if oft_node isa OfArray
                # Calculate number of elements needed
                n_elements = prod(oft_node.dims)
                if pos[] + n_elements - 1 > length(flat_values)
                    error(
                        "Not enough values in flat array: need $(pos[] + n_elements - 1), have $(length(flat_values))",
                    )
                end
                # Extract values and reshape
                values = flat_values[pos[]:(pos[] + n_elements - 1)]
                pos[] += n_elements
                return reshape(values, oft_node.dims)
            elseif oft_node isa OfReal
                if pos[] > length(flat_values)
                    error(
                        "Not enough values in flat array: need $(pos[]), have $(length(flat_values))",
                    )
                end
                val = flat_values[pos[]]
                pos[] += 1
                # Apply bounds validation
                if !isnothing(oft_node.lower) && val < oft_node.lower
                    error("Value $val is below lower bound $(oft_node.lower)")
                end
                if !isnothing(oft_node.upper) && val > oft_node.upper
                    error("Value $val is above upper bound $(oft_node.upper)")
                end
                return val
            else
                error("Unknown leaf type: $(typeof(oft_node))")
            end
        elseif oft_node isa OfNamedTuple
            # Reconstruct each field
            values = map(reconstruct_node, oft_node.types)
            names = get_names(oft_node)
            return NamedTuple{names}(values)
        else
            error("Unknown node type: $(typeof(oft_node))")
        end
    end

    reconstructed = reconstruct_node(oft)

    # Check that we used all values
    if pos[] - 1 != length(flat_values)
        error(
            "Unused values in flat array: used $(pos[] - 1), provided $(length(flat_values))",
        )
    end

    return reconstructed
end

"""
    tree_map_with_path(f, of_type)

Apply function `f(path, leaf)` to all leaf nodes, where path is a tuple of keys/indices.
Uses Functors.jl's fmap_with_path.
"""
function tree_map_with_path(f, oft::OfType)
    return Functors.fmap_with_path(oft; exclude=(kp, x) -> is_leaf(x)) do kp, x
        f(Tuple(kp), x)
    end
end

"""
    validate(of_type, value)

Validate and convert a Julia value to match the structure of an OfType specification.
This ensures values conform to the expected types, dimensions, and bounds.
"""
function validate(oft::OfType, value)
    if is_leaf(oft)
        return validate_leaf(oft, value)
    else
        return validate_container(oft, value)
    end
end

function validate_container(oft::OfNamedTuple{names,T}, value) where {names,T}
    if value isa NamedTuple
        # Build a new NamedTuple with canonicalized values
        # Use the fact that we can iterate over the indices
        vals = ntuple(length(oft.types)) do i
            # Get the field name from the type parameter
            field_name = names[i]
            # Validate the corresponding value
            validate(oft.types[i], getproperty(value, field_name))
        end
        return NamedTuple{names}(vals)
    else
        error("Expected NamedTuple for OfNamedTuple, got $(typeof(value))")
    end
end

function validate_leaf(oft::OfArray{T,N}, value) where {T,N}
    if value isa AbstractArray
        # Convert to the expected array type and dimensions
        arr = convert(Array{T,N}, value)
        if size(arr) != oft.dims
            error("Array dimensions mismatch: expected $(oft.dims), got $(size(arr))")
        end
        return arr
    else
        error("Expected Array for OfArray, got $(typeof(value))")
    end
end

function validate_leaf(oft::OfReal, value)
    if value isa Real
        val = convert(Float64, value)
        # Check bounds
        if !isnothing(oft.lower) && val < oft.lower
            error("Value $val is below lower bound $(oft.lower)")
        end
        if !isnothing(oft.upper) && val > oft.upper
            error("Value $val is above upper bound $(oft.upper)")
        end
        return val
    else
        error("Expected Real for OfReal, got $(typeof(value))")
    end
end

# Fallback for unknown leaf types
validate_leaf(oft::OfType, value) = error("No validate_leaf method for $(typeof(oft))")

# Fallback for unknown container types
function validate_container(oft::OfType, value)
    return error("No validate_container method for $(typeof(oft))")
end
