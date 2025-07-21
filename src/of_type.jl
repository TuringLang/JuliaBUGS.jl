using Random: randexp

# ========================================================================
# Core Type Definitions
# ========================================================================

"""
    OfType

Abstract base type for all types in the `of` type system.

The `of` type system provides a declarative way to specify parameter types for 
probabilistic programming. All `of` types encode their specifications (dimensions, 
bounds, etc.) in type parameters, allowing them to be used as actual Julia types 
in type annotations.

# Subtypes
- `OfReal{T,Lower,Upper}`: Bounded or unbounded floating-point numbers
- `OfInt{Lower,Upper}`: Bounded or unbounded integers  
- `OfArray{T,N,Dims}`: Arrays with specified element type and dimensions
- `OfNamedTuple{Names,Types}`: Named tuples with typed fields
- `OfConstantWrapper{T}`: Wrapper marking a type as constant/hyperparameter

# See also
[`of`](@ref), [`@of`](@ref)
"""
abstract type OfType end

"""
    SymbolicRef{S}

Wrapper type for symbolic references in bounds and dimensions.

Used internally to encode references to other fields when specifying bounds or dimensions 
that depend on constant fields. For example, when using `@of(n=of(Int; constant=true), 
data=of(Array, n, 2))`, the reference to `n` in the array dimension is encoded as 
`SymbolicRef{:n}`.

# Type Parameters
- `S`: The symbol being referenced

# See also
[`@of`](@ref), [`of`](@ref)
"""
struct SymbolicRef{S} end

"""
    SymbolicExpr{E}

Wrapper type for symbolic expressions in dimensions.

Used internally to encode arithmetic expressions involving constant fields or other parameters. For example,
when using `@of(n=of(Int; constant=true), padded=of(Array, n+1, n+1))`, the expression 
`n+1` is encoded as `SymbolicExpr{(:+, :n, 1)}`.

Supported operations: `+`, `-`, `*`, `/`. Division operations must result in integers 
when used for array dimensions.

# Type Parameters
- `E`: A tuple representing the expression in prefix notation

# See also
[`@of`](@ref), [`of`](@ref)
"""
struct SymbolicExpr{E} end

"""
    OfReal{T<:AbstractFloat,Lower,Upper}

Type specification for bounded or unbounded floating-point numbers.

# Type Parameters
- `T<:AbstractFloat`: The concrete floating-point type (e.g., `Float64`, `Float32`)
- `Lower`: Lower bound (numeric value, `Nothing` for unbounded, or `SymbolicRef`)
- `Upper`: Upper bound (numeric value, `Nothing` for unbounded, or `SymbolicRef`)

# Examples
```julia
of(Float64)              # OfReal{Float64, Nothing, Nothing}
of(Float32, 0.0, 1.0)    # OfReal{Float32, 0.0, 1.0}
of(Real, 0, nothing)     # OfReal{Float64, 0, Nothing} (defaults to Float64)
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
struct OfReal{T<:AbstractFloat,Lower,Upper} <: OfType
    function OfReal{T,L,U}() where {T<:AbstractFloat,L,U}
        return error(
            "OfReal is a type specification, not an instantiable object. Use of(Float64, ...) or of(Float32, ...) to create the type.",
        )
    end
end

"""
    OfInt{Lower,Upper}

Type specification for bounded or unbounded integers.

# Type Parameters
- `Lower`: Lower bound (integer value, `Nothing` for unbounded, or `SymbolicRef`)
- `Upper`: Upper bound (integer value, `Nothing` for unbounded, or `SymbolicRef`)

# Examples
```julia
of(Int)           # OfInt{Nothing, Nothing}
of(Int, 1, 10)    # OfInt{1, 10}
of(Int, 0, nothing)  # OfInt{0, Nothing}
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
struct OfInt{Lower,Upper} <: OfType
    function OfInt{L,U}() where {L,U}
        return error(
            "OfInt is a type specification, not an instantiable object. Use of(Int, ...) to create the type.",
        )
    end
end

"""
    OfArray{T,N,Dims}

Type specification for arrays with fixed element type and dimensions.

# Type Parameters
- `T`: Element type of the array
- `N`: Number of dimensions
- `Dims`: Tuple type encoding the size of each dimension (can include `SymbolicRef` or `SymbolicExpr`)

# Examples
```julia
of(Array, 3, 4)          # OfArray{Float64, 2, (3, 4)}
of(Array, Float32, 10)   # OfArray{Float32, 1, (10,)}
@of(n=of(Int; constant=true), data=of(Array, n, 2))  # Symbolic dimension
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
struct OfArray{T,N,Dims} <: OfType
    function OfArray{T,N,D}() where {T,N,D}
        return error(
            "OfArray is a type specification, not an instantiable object. Use of(Array, ...) to create the type.",
        )
    end
end

"""
    OfNamedTuple{Names,Types<:Tuple}

Type specification for named tuples with typed fields.

# Type Parameters
- `Names`: Tuple of field names as symbols
- `Types<:Tuple`: Tuple of field types (each must be an `OfType`)

# Examples
```julia
@of(mu=of(Real), tau=of(Real, 0, nothing))
of((a=of(Int), b=of(Array, 3, 3)))
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
struct OfNamedTuple{Names,Types<:Tuple} <: OfType
    function OfNamedTuple{Names,Types}() where {Names,Types}
        return error(
            "OfNamedTuple is a type specification, not an instantiable object. Use of(...) to create the type.",
        )
    end
end

"""
    OfConstantWrapper{T<:OfType}

Wrapper type marking a field as a constant/hyperparameter.

Constants are not included in flattened representations and must be provided
when creating instances or concretizing types with symbolic dimensions.

# Type Parameters
- `T<:OfType`: The wrapped type specification

# Examples
```julia
of(Int; constant=true)    # OfConstantWrapper{OfInt{Nothing, Nothing}}
of(Real; constant=true)   # OfConstantWrapper{OfReal{Float64, Nothing, Nothing}}
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
struct OfConstantWrapper{T<:OfType} <: OfType
    function OfConstantWrapper{T}() where {T<:OfType}
        return error(
            "OfConstantWrapper is a type specification, not an instantiable object. Use of(...; constant=true) to create the type.",
        )
    end
end

# ========================================================================
# Type Parameter Extraction Helpers
# ========================================================================
get_lower(::Type{OfReal{T,L,U}}) where {T,L,U} = L
get_upper(::Type{OfReal{T,L,U}}) where {T,L,U} = U
get_element_type(::Type{OfReal{T,L,U}}) where {T,L,U} = T
get_lower(::Type{OfInt{L,U}}) where {L,U} = L
get_upper(::Type{OfInt{L,U}}) where {L,U} = U
get_element_type(::Type{OfArray{T,N,D}}) where {T,N,D} = T
get_ndims(::Type{OfArray{T,N,D}}) where {T,N,D} = N
function get_dims(::Type{OfArray{T,N,D}}) where {T,N,D}
    return D isa DataType && D <: Tuple ? tuple(D.parameters...) : D
end
get_names(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Names
get_types(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Types
get_wrapped_type(::Type{OfConstantWrapper{T}}) where {T} = T

# ========================================================================
# Type Classification and Conversion Utilities
# ========================================================================

# Check if a type is a leaf
is_leaf(::Type{<:OfArray}) = true
is_leaf(::Type{<:OfReal}) = true
is_leaf(::Type{<:OfInt}) = true
is_leaf(::Type{<:OfNamedTuple}) = false
is_leaf(::Type{<:OfConstantWrapper}) = true

# Convert bounds to type parameters
bound_to_type(::Nothing) = Nothing
bound_to_type(x::Real) = x
bound_to_type(s::Symbol) = SymbolicRef{s}
bound_to_type(s::QuoteNode) = SymbolicRef{s.value}

# Extract value from type parameter
type_to_bound(::Type{Nothing}) = nothing
type_to_bound(::Type{x}) where {x<:Real} = x  # Extract numeric type parameter
type_to_bound(::Type{SymbolicRef{S}}) where {S} = S
type_to_bound(s::Symbol) = s
type_to_bound(x::Real) = x  # Pass through numeric values

# ========================================================================
# Symbolic Expression Evaluation
# ========================================================================
function eval_symbolic_expr(expr::Tuple, bindings::NamedTuple)
    if length(expr) < 2
        error("Invalid expression format: $expr")
    end

    op = expr[1]
    if !(op in (:+, :-, :*, :/))
        error("Unsupported operation: $op. Only +, -, *, / are supported.")
    end

    # Evaluate arguments recursively
    args = map(expr[2:end]) do arg
        if arg isa Symbol
            if haskey(bindings, arg)
                bindings[arg]
            else
                error("Symbol '$arg' not found in bindings")
            end
        elseif arg isa Tuple
            eval_symbolic_expr(arg, bindings)
        else
            arg
        end
    end

    # Apply operation
    if op == :+
        return sum(args)
    elseif op == :-
        return length(args) == 1 ? -args[1] : args[1] - args[2]
    elseif op == :*
        return prod(args)
    elseif op == :/
        if length(args) != 2
            error("Division requires exactly 2 arguments")
        end
        result = args[1] / args[2]
        # For array dimensions, ensure the result is an integer
        if isinteger(args[1]) && !isinteger(result)
            error(
                "Division $(args[1]) / $(args[2]) = $result is not an integer. Array dimensions must be integers.",
            )
        end
        return Int(result)
    end
end

# ========================================================================
# Type Concretization and Resolution
# ========================================================================

# Resolve bound references during type concretization
function resolve_bound(::Type{Nothing}, replacements::NamedTuple)
    return Nothing
end

function resolve_bound(::Type{x}, replacements::NamedTuple) where {x<:Real}
    return x
end

function resolve_bound(::Type{SymbolicRef{S}}, replacements::NamedTuple) where {S}
    if haskey(replacements, S)
        return bound_to_type(replacements[S])
    else
        return SymbolicRef{S}
    end
end

function resolve_bound(::Type{SymbolicExpr{E}}, replacements::NamedTuple) where {E}
    # Evaluate the expression with current replacements
    evaluated = eval_symbolic_expr(E, replacements)
    return bound_to_type(evaluated)
end

function resolve_bound(T::Type, ::NamedTuple)
    return T
end

# Handle numeric bounds
function resolve_bound(x::Real, ::NamedTuple)
    return x
end

# ========================================================================
# Helper Functions for Constructors
# ========================================================================

# Process array dimensions into a proper tuple type
function process_array_dimensions(dims)
    processed_dims = map(dims) do d
        if d isa QuoteNode
            d.value
        elseif d isa Type
            # Keep type parameters as-is (e.g., SymbolicExpr{...})
            d
        else
            d
        end
    end
    # Ensure we have a tuple of dimensions
    if length(processed_dims) == 1
        Tuple{processed_dims[1]}
    else
        Tuple{processed_dims...}
    end
end

# Process bounds for Int/Real types
function process_bounds(lower, upper)
    L = if lower isa Type
        lower
    else
        bound_to_type(lower)
    end
    U = if upper isa Type
        upper
    else
        bound_to_type(upper)
    end
    return L, U
end

# ========================================================================
# Constructor Functions
# ========================================================================

"""
    of(T, args...; constant::Bool=false)

Create an `OfType` specification from various inputs.

# Main Methods

## Arrays
```julia
of(Array, dims...)              # Float64 array with given dimensions
of(Array, T, dims...)           # Array with element type T and given dimensions
```

## Real Numbers
```julia
of(Float64)                     # Unbounded Float64
of(Float64, lower, upper)       # Bounded Float64
of(Float32)                     # Unbounded Float32
of(Float32, lower, upper)       # Bounded Float32
of(Real)                        # Unbounded Real (defaults to Float64)
of(Real, lower, upper)          # Bounded Real (defaults to Float64)
```

## Integers
```julia
of(Int)                         # Unbounded integer
of(Int, lower, upper)           # Bounded integer
```

## Named Tuples
```julia
of((;field1=spec1, field2=spec2, ...))  # NamedTuple with typed fields
```

## From Values (Type Inference)
```julia
of(1.0)                         # Infers of(Float64)
of([1, 2, 3])                   # Infers of(Array, Int, 3)
of((a=1, b=2.0))               # Infers OfNamedTuple
```

# Arguments
- `T`: Type to create specification for
- `args...`: Type-specific arguments (bounds, dimensions, etc.)
- `constant`: Mark type as constant/hyperparameter (default: false)

# Returns
An `OfType` subtype encoding the specification in its type parameters.

# Examples
```julia
# Basic types
T1 = of(Float64, 0, 1)          # OfReal{Float64, 0, 1}
T2 = of(Array, 3, 4)            # OfArray{Float64, 2, (3, 4)}
T3 = of(Int; constant=true)     # OfConstantWrapper{OfInt{Nothing, Nothing}}

# With @of macro for cleaner syntax
T4 = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)      # Symbolic dimension
)

# Type concretization
T5 = of(T4; n=10)               # Concrete type with n=10
```

# See also
[`@of`](@ref), [`OfType`](@ref)
"""
function of(::Type{Array}, dims...; constant::Bool=false)
    if constant
        error("constant=true is only supported for Int and Real types, not Array")
    end
    # Default to Float64 for unspecified array types
    dims_tuple = process_array_dimensions(dims)
    return OfArray{Float64,length(dims),dims_tuple}
end

function of(::Type{Array}, T::Type, dims...; constant::Bool=false)
    # Check if T is a symbolic expression type (which should be treated as a dimension)
    if T <: SymbolicExpr
        # This is actually a dimension, not an element type
        # Construct the array type directly with Float64 as element type
        if constant
            error("constant=true is only supported for Int and Real types, not Array")
        end
        all_dims = (T, dims...)
        dims_tuple = process_array_dimensions(all_dims)
        return OfArray{Float64,length(all_dims),dims_tuple}
    end

    if constant
        error("constant=true is only supported for Int and Real types, not Array")
    end
    dims_tuple = process_array_dimensions(dims)
    return OfArray{T,length(dims),dims_tuple}
end

function of(::Type{Int}; constant::Bool=false)
    base_type = OfInt{Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{Int},
    lower::Union{Int,Nothing,Symbol,Type},
    upper::Union{Int,Nothing,Symbol,Type};
    constant::Bool=false,
)
    L, U = process_bounds(lower, upper)
    base_type = OfInt{L,U}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(::Type{T}; constant::Bool=false) where {T<:AbstractFloat}
    base_type = OfReal{T,Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{T},
    lower::Union{Real,Nothing,Symbol,Type},
    upper::Union{Real,Nothing,Symbol,Type};
    constant::Bool=false,
) where {T<:AbstractFloat}
    L, U = process_bounds(lower, upper)
    base_type = OfReal{T,L,U}
    return constant ? OfConstantWrapper{base_type} : base_type
end

# of(Real) creates Float64
function of(::Type{Real}; constant::Bool=false)
    base_type = OfReal{Float64,Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{Real},
    lower::Union{Real,Nothing,Symbol,Type},
    upper::Union{Real,Nothing,Symbol,Type};
    constant::Bool=false,
)
    L, U = process_bounds(lower, upper)
    base_type = OfReal{Float64,L,U}
    return constant ? OfConstantWrapper{base_type} : base_type
end

# Infer OfType from concrete values
function of(value::T) where {T<:AbstractFloat}
    return of(T)
end

function of(value::Integer)
    return of(Int)
end

# Fallback for other Real types
function of(value::Real)
    return of(Float64)  # Non-float Real types use Float64
end

function of(value::AbstractArray{T,N}) where {T,N}
    return of(Array, T, size(value)...)
end

function of(value::NamedTuple{names}) where {names}
    # Check if all values are already OfType types
    vals = values(value)
    if all(v -> v isa Type && v <: OfType, vals)
        # This is a NamedTuple of types, not values
        return OfNamedTuple{names,Tuple{vals...}}
    else
        # This is a NamedTuple of values, infer types
        of_types = map(of, vals)
        return OfNamedTuple{names,Tuple{of_types...}}
    end
end

# ========================================================================
# Helper Functions for Type Concretization
# ========================================================================

# Resolve bounds in a bounded type (OfReal or OfInt)
function resolve_bounded_type(::Type{T}, replacements::NamedTuple) where {T<:OfType}
    if !(T <: OfReal || T <: OfInt)
        return T
    end

    lower = get_lower(T)
    upper = get_upper(T)
    new_lower = resolve_bound(lower, replacements)
    new_upper = resolve_bound(upper, replacements)

    if new_lower !== lower || new_upper !== upper
        # Create new type with resolved bounds
        if T <: OfReal
            elem_type = get_element_type(T)
            return OfReal{elem_type,new_lower,new_upper}
        elseif T <: OfInt
            return OfInt{new_lower,new_upper}
        end
    else
        return T
    end
end

# ========================================================================
# Type Concretization with Replacements
# ========================================================================

"""
    of(::Type{T}, replacements::NamedTuple) where T<:OfType
    of(::Type{T}; kwargs...) where T<:OfType
    of(::Type{T}, pairs::Pair{Symbol}...) where T<:OfType

Create a concrete type by resolving symbolic dimensions and removing constants.

This function takes an `OfType` with symbolic dimensions or constants and creates
a new type with some or all symbols resolved to concrete values. Constants that
are provided are removed from the resulting type.

# Arguments
- `T<:OfType`: The type to concretize
- `replacements`: Named tuple or keyword arguments mapping symbols to values

# Returns
A new `OfType` with symbols replaced and constants removed.

# Examples
```julia
# Define type with symbolic dimensions
T = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)
)

# Create concrete type
ConcreteT = of(T; n=10)      # @of(data=of(Array, 10, 2))

# Partial concretization
T2 = @of(
    rows = of(Int; constant=true),
    cols = of(Int; constant=true),
    matrix = of(Array, rows, cols)
)
Partial = of(T2; rows=5)     # @of(cols=of(Int; constant=true), matrix=of(Array, 5, :cols))
```

# See also
[`of`](@ref), [`@of`](@ref)
"""
function of(::Type{T}, pairs::Pair{Symbol}...) where {T<:OfType}
    return of(T, NamedTuple(pairs))
end

function of(::Type{T}; kwargs...) where {T<:OfType}
    return of(T, NamedTuple(kwargs))
end

# Helper function to resolve dimensions with replacements
function _resolve_dimensions(dims, replacements::NamedTuple)
    return map(dims) do d
        if d isa Symbol && haskey(replacements, d)
            replacements[d]
        elseif d isa Type && d <: SymbolicExpr
            # Evaluate the expression
            expr = d.parameters[1]
            eval_symbolic_expr(expr, replacements)
        else
            d
        end
    end
end

# Helper function to process a single field for concretization
function _process_field_for_concretization(
    name::Symbol, field_type::Type, replacements::NamedTuple
)
    # Case 1: Constant field that has been resolved - skip it
    if field_type <: OfConstantWrapper && haskey(replacements, name)
        return nothing
    end

    # Case 2: Array with potentially symbolic dimensions
    if field_type <: OfArray
        dims = get_dims(field_type)
        new_dims = _resolve_dimensions(dims, replacements)

        if new_dims != dims
            # Create new array type with concrete dimensions
            T = get_element_type(field_type)
            return (name, of(Array, T, new_dims...))
        else
            return (name, field_type)
        end
    end

    # Case 3: Nested NamedTuple - recursively concretize
    if field_type <: OfNamedTuple
        return (name, of(field_type, replacements))
    end

    # Case 4: Bounded types (Real/Int) with potentially symbolic bounds
    if field_type <: OfReal || field_type <: OfInt
        return (name, resolve_bounded_type(field_type, replacements))
    end

    # Case 5: Constant wrapper without replacement - resolve wrapped type
    if field_type <: OfConstantWrapper
        wrapped = get_wrapped_type(field_type)
        resolved = resolve_bounded_type(wrapped, replacements)

        if resolved !== wrapped
            return (name, OfConstantWrapper{resolved})
        else
            return (name, field_type)
        end
    end

    # Case 6: Other types - pass through unchanged
    return (name, field_type)
end

function of(::Type{OfNamedTuple{Names,Types}}, replacements::NamedTuple) where {Names,Types}
    # Process each field and collect the results
    processed_fields = []

    for i in 1:length(Names)
        name = Names[i]
        field_type = Types.parameters[i]

        result = _process_field_for_concretization(name, field_type, replacements)

        if !isnothing(result)
            push!(processed_fields, result)
        end
    end

    # Check if any fields remain
    if isempty(processed_fields)
        error("All fields were constants and have been resolved. No fields remain.")
    end

    # Extract names and types from processed fields
    remaining_names = [field[1] for field in processed_fields]
    remaining_types = [field[2] for field in processed_fields]

    return OfNamedTuple{Tuple(remaining_names),Tuple{remaining_types...}}
end

function of(::Type{OfArray{T,N,D}}, replacements::NamedTuple) where {T,N,D}
    # Replace symbolic dimensions in array types
    dims = get_dims(OfArray{T,N,D})
    new_dims = _resolve_dimensions(dims, replacements)
    return OfArray{T,N,Tuple{new_dims...}}
end

function of(::Type{T}, replacements::NamedTuple) where {T<:OfType}
    # For other types (OfReal, OfConstantWrapper), just return as-is
    return T
end

# ========================================================================
# Helper for creating values with default
# ========================================================================
function _create_with_default(::Type{OfArray{T,N,D}}, default_value) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot create array with symbolic dimensions. Use T(default_value; kwargs...) with dimension values.",
        )
    end
    # Handle missing values specially - create array of Union{T,Missing}
    if default_value === missing
        return fill(missing, dims...)
    else
        return fill(convert(T, default_value), dims...)
    end
end

function _create_with_default(::Type{OfReal{T,L,U}}, default_value) where {T,L,U}
    # Handle missing separately
    if default_value === missing
        return missing
    end
    val = convert(T, default_value)
    lower = type_to_bound(L)
    upper = type_to_bound(U)
    validate_bounds(val, lower, upper, "Real")
    return val
end

function _create_with_default(::Type{OfInt{L,U}}, default_value) where {L,U}
    # Handle missing separately
    if default_value === missing
        return missing
    end
    # Use round for converting floats to ints
    val = if isa(default_value, Integer)
        convert(Int, default_value)
    else
        round(Int, default_value)
    end
    lower = type_to_bound(L)
    upper = type_to_bound(U)
    validate_bounds(val, lower, upper, "Int")
    return val
end

function _create_with_default(
    ::Type{OfNamedTuple{Names,Types}}, default_value
) where {Names,Types}
    values = Tuple(
        _create_with_default(Types.parameters[i], default_value) for i in 1:length(Names)
    )
    return NamedTuple{Names}(values)
end

function _create_with_default(::Type{OfConstantWrapper{T}}, default_value) where {T}
    return error(
        "Cannot create values for constants. Provide the constant value in T(; const_name=value).",
    )
end

# ========================================================================
# Helper function for instance creation
# ========================================================================
function _create_instance_impl(
    ::Type{T}, value_generator::Function, kwargs
) where {T<:OfType}
    if !(T <: OfNamedTuple)
        error("Instance creation is only supported for OfNamedTuple types, not $(T)")
    end

    names = get_names(T)
    types = get_types(T)

    # Separate constants from values
    constants = Dict{Symbol,Any}()
    values = Dict{Symbol,Any}()

    for (key, val) in pairs(kwargs)
        idx = findfirst(==(key), names)
        if idx !== nothing && types.parameters[idx] <: OfConstantWrapper
            constants[key] = val
        else
            values[key] = val
        end
    end

    # Check that all constants are provided
    for (idx, name) in enumerate(names)
        if types.parameters[idx] <: OfConstantWrapper && !haskey(constants, name)
            error("Constant `$name` is required but not provided")
        end
    end

    # First concretize with constants
    concrete_type = of(T, NamedTuple(constants))

    # Check if all constants are resolved
    if has_symbolic_dims(concrete_type)
        missing_symbols = get_unresolved_symbols(concrete_type)
        error("Missing values for symbolic dimensions: $(join(missing_symbols, ", "))")
    end

    # Get the names and types from the concrete type (constants removed)
    concrete_names = get_names(concrete_type)
    concrete_types = get_types(concrete_type)

    # Build the result with provided values or defaults
    result_values = Any[]
    for (idx, name) in enumerate(concrete_names)
        field_type = concrete_types.parameters[idx]

        if haskey(values, name)
            # Validate the provided value
            try
                push!(result_values, _validate(field_type, values[name]))
            catch e
                error("Validation failed for field $name: $(e.msg)")
            end
        else
            # Use the value generator function
            push!(result_values, value_generator(field_type))
        end
    end

    # Return the instance as a NamedTuple
    return NamedTuple{concrete_names}(Tuple(result_values))
end

# ========================================================================
# Parameterized Constructor with Validation
# ========================================================================

"""
    (::Type{T})(; kwargs...) where {T<:OfType}
    (::Type{T})(default_value; kwargs...) where {T<:OfType}

Create an instance of an `OfNamedTuple` type with specified constant values.

This constructor creates actual values (instances) from `OfType` specifications.
It requires all constants to be provided and initializes non-constant fields
to zero or a specified default value.

# Arguments
- `T<:OfType`: Must be an `OfNamedTuple` type
- `default_value`: Optional value to initialize all non-constant fields (default: appropriate zero)
- `kwargs...`: Constant values and optionally non-constant field values

# Returns
A `NamedTuple` instance with all fields initialized.

# Examples
```julia
# Define type with constants
T = @of(
    n = of(Int; constant=true),
    mu = of(Real),
    data = of(Array, n, 2)
)

# Create instance with constants (non-constants default to zero)
instance = T(; n=5)
# Returns: (mu = 0.0, data = zeros(5, 2))

# Create instance with custom default
instance = T(1.0; n=5)  
# Returns: (mu = 1.0, data = ones(5, 2))

# Create instance with missing values
instance = T(missing; n=5)
# Returns: (mu = missing, data = 5×2 Array{Missing})

# Provide specific values for non-constants
instance = T(; n=5, mu=2.5, data=rand(5, 2))
# Returns: (mu = 2.5, data = <provided 5×2 array>)
```

# Errors
- Throws error if required constants are not provided
- Throws error if this is called on non-NamedTuple types

# See also
[`of`](@ref), [`@of`](@ref)
"""
function (::Type{T})(; kwargs...) where {T<:OfType}
    return _create_instance_impl(T, zero, kwargs)
end

# Constructor with default_value as positional argument
function (::Type{T})(default_value; kwargs...) where {T<:OfType}
    return _create_instance_impl(
        T, field_type -> _create_with_default(field_type, default_value), kwargs
    )
end

# ========================================================================
# @of Macro and Related Processing Functions
# ========================================================================

"""
    @of(field1=spec1, field2=spec2, ...)

Create an `OfNamedTuple` type with cleaner syntax for field references.

The `@of` macro provides a more intuitive syntax for creating named tuple types
where fields can reference each other. Field names used in dimensions or bounds
are automatically converted to symbolic references.

# Syntax
```julia
@of(
    field_name = of_specification,
    ...
)
```

# Features
- Direct field references without quoting (e.g., `n` instead of `:n`)
- Support for arithmetic expressions in dimensions (e.g., `n+1`, `2*n`)
- Automatic conversion to appropriate `OfNamedTuple` type
- Fields are processed in order, allowing later fields to reference earlier ones

# Examples
```julia
# Basic usage with constants and arrays
T = @of(
    n = of(Int; constant=true),
    mu = of(Real),
    data = of(Array, n, 2)  # 'n' automatically converted to symbolic reference
)

# With arithmetic expressions
T = @of(
    n = of(Int; constant=true),
    original = of(Array, n, n),
    padded = of(Array, n+1, n+1),
    doubled = of(Array, 2*n, n)
)

# Nested structures
T = @of(
    dims = @of(
        rows = of(Int; constant=true),
        cols = of(Int; constant=true)
    ),
    matrix = of(Array, dims.rows, dims.cols)
)
```

# See also
[`of`](@ref), [`OfNamedTuple`](@ref)
"""
macro of(args...)
    # Parse the arguments to extract field specifications
    fields = Dict{Symbol,Any}()
    field_order = Symbol[]

    for arg in args
        if !(arg isa Expr && arg.head == :(=) && length(arg.args) == 2)
            error("@of expects keyword arguments like field=spec")
        end

        field_name = arg.args[1]
        field_spec = arg.args[2]

        if field_name isa Symbol
            fields[field_name] = field_spec
            push!(field_order, field_name)
        else
            error("Field name must be a symbol, got $(field_name)")
        end
    end

    # Process each field specification, converting references to symbols
    processed_fields = Dict{Symbol,Any}()

    for (field_name, spec) in fields
        processed_spec = process_of_spec(spec, field_order)
        processed_fields[field_name] = processed_spec
    end

    # Build the named tuple expression
    nt_expr = Expr(:tuple)
    for field_name in field_order
        push!(nt_expr.args, Expr(:(=), field_name, processed_fields[field_name]))
    end

    # Return the of call
    return esc(:(of($nt_expr)))
end

# Process an of specification, converting field references to symbols
function process_of_spec(spec::Expr, available_fields::Vector{Symbol})
    if spec.head == :call && length(spec.args) >= 1
        func = spec.args[1]

        # Check if this is an of(...) call
        if func == :of
            # Process the arguments
            new_args = Any[func]

            # Separate positional and keyword arguments
            pos_args = []
            kw_args = []

            for arg in spec.args[2:end]
                if arg isa Expr && arg.head == :parameters
                    # Handle parameters block (e.g., f(x; a=1, b=2))
                    for param in arg.args
                        push!(kw_args, param)
                    end
                elseif arg isa Expr && arg.head == :kw
                    # Handle individual keyword argument
                    push!(kw_args, arg)
                else
                    # Positional argument
                    push!(pos_args, arg)
                end
            end

            # Process positional arguments
            for arg in pos_args
                processed_arg = process_dimension_arg(arg, available_fields)
                push!(new_args, processed_arg)
            end

            # Add keyword arguments as-is
            if !isempty(kw_args)
                params_expr = Expr(:parameters, kw_args...)
                insert!(new_args, 2, params_expr)
            end

            return Expr(:call, new_args...)
        else
            # Not an of call, process recursively
            return Expr(
                spec.head, [process_of_spec(arg, available_fields) for arg in spec.args]...
            )
        end
    else
        return spec
    end
end

process_of_spec(x, ::Vector{Symbol}) = x

# Process a dimension/bound argument, converting field references to symbols
function process_dimension_arg(arg, available_fields::Vector{Symbol})
    if arg isa Symbol && arg in available_fields
        # Convert field reference to symbol
        return QuoteNode(arg)
    elseif arg isa Expr
        # Check for expressions containing field references
        return process_expression_refs(arg, available_fields)
    else
        # Leave other values as-is
        return arg
    end
end

# Check if a processed expression is a SymbolicExpr type
function _is_symbolic_expr_type(expr::Expr)
    return expr.head == :curly && length(expr.args) >= 2 && expr.args[1] == :SymbolicExpr
end

# Process a single argument in an arithmetic expression
function _process_arithmetic_arg(arg, available_fields::Vector{Symbol})
    if arg isa Symbol && arg in available_fields
        # Field reference - convert to quoted symbol
        return (QuoteNode(arg), true)
    elseif arg isa Expr
        # Recursively process sub-expressions
        processed = process_expression_refs(arg, available_fields)
        if _is_symbolic_expr_type(processed)
            # Extract the tuple from SymbolicExpr{...}
            return (processed.args[2], true)
        else
            return (processed, false)
        end
    else
        # Literal value - keep as-is
        return (arg, false)
    end
end

# Process an arithmetic expression, converting field references to symbols
function _process_arithmetic_expr(expr::Expr, available_fields::Vector{Symbol})
    op = expr.args[1]

    # Build tuple representation: (op, arg1, arg2, ...)
    tuple_args = Any[QuoteNode(op)]
    has_field_ref = false

    # Process each argument
    for arg in expr.args[2:end]
        processed_arg, has_ref = _process_arithmetic_arg(arg, available_fields)
        push!(tuple_args, processed_arg)
        has_field_ref |= has_ref
    end

    if has_field_ref
        # Create SymbolicExpr type with tuple
        tuple_expr = Expr(:tuple, tuple_args...)
        return :(SymbolicExpr{$tuple_expr})
    else
        # No field references - return original expression
        return expr
    end
end

# Process an expression, converting field references to symbols in expressions
function process_expression_refs(expr::Expr, available_fields::Vector{Symbol})
    # Check if this is an arithmetic call expression
    if expr.head == :call && length(expr.args) >= 2
        op = expr.args[1]
        if op in [:+, :-, :*, :/]
            return _process_arithmetic_expr(expr, available_fields)
        end
    end

    # Not a supported arithmetic expression - return as-is
    return expr
end

# ========================================================================
# Random Value Generation
# ========================================================================

"""
    rand(::Type{T}) where T<:OfType

Generate random values matching the type specification.

Creates random instances that satisfy the constraints encoded in the `OfType`.
Arrays are filled with random values, bounded types respect their bounds,
and named tuples recursively generate random values for all fields.

# Supported Types
- `OfReal`: Generates values within bounds (uniform for bounded, normal for unbounded)
- `OfInt`: Generates integers within bounds  
- `OfArray`: Generates arrays with random elements
- `OfNamedTuple`: Recursively generates random values for all fields
- `OfConstantWrapper`: Not supported (throws error)

# Examples
```julia
# Bounded real
T1 = of(Float64, 0, 1)
rand(T1)  # Random Float64 in [0, 1]

# Array 
T2 = of(Array, 3, 4)
rand(T2)  # 3×4 matrix of random Float64s

# Named tuple
T3 = @of(x=of(Real, 0, 1), y=of(Array, 2, 2))
rand(T3)  # (x=0.7, y=[0.3 0.8; 0.2 0.5])

# With resolved constants
T4 = @of(n=of(Int; constant=true), data=of(Array, n, 2))
rand(of(T4; n=5))  # (data = 5×2 random array)
```

# Errors
- Throws error for types with unresolved symbolic dimensions
- Throws error for constant wrapper types

# See also
[`zero`](@ref), [`of`](@ref)
"""
function Base.rand(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot generate random array with symbolic dimensions. Use rand(T; kwargs...) with dimension values.",
        )
    end
    return rand(T, dims...)
end

function Base.rand(::Type{OfReal{T,L,U}}) where {T,L,U}
    val = rand()
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && !isnothing(upper)
        return T(lower + val * (upper - lower))
    elseif !isnothing(lower)
        # For lower bound only, generate values in [lower, ∞)
        # Using exponential distribution shifted by lower
        return T(lower + randexp())
    elseif !isnothing(upper)
        # For upper bound only, generate values in (-∞, upper]
        # Using negative exponential distribution shifted by upper
        return T(upper - randexp())
    else
        return T(randn())  # Use normal distribution for unbounded
    end
end

function Base.rand(::Type{OfInt{L,U}}) where {L,U}
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && !isnothing(upper)
        # Generate random integer in [lower, upper]
        return rand(lower:upper)
    elseif !isnothing(lower)
        # For lower bound only, generate values in [lower, lower+100]
        # This is arbitrary but provides reasonable default behavior
        return rand(lower:(lower + 100))
    elseif !isnothing(upper)
        # For upper bound only, generate values in [upper-100, upper]
        return rand((upper - 100):upper)
    else
        # Unbounded integer - generate in reasonable range
        return rand(-100:100)
    end
end

function Base.rand(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(rand(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

function Base.rand(::Type{OfConstantWrapper{T}}) where {T}
    return error(
        "Cannot generate random values for constants. Use rand(of(T; const_name=value)) after providing the constant value.",
    )
end

# ========================================================================
# Zero Value Generation
# ========================================================================

"""
    zero(::Type{T}) where T<:OfType

Generate zero/default values matching the type specification.

Creates instances initialized to appropriate zero values that satisfy the 
constraints. For bounded types where zero is outside the bounds, returns 
the nearest bound value.

# Behavior by Type
- `OfReal`: Returns 0.0 if within bounds, otherwise nearest bound
- `OfInt`: Returns 0 if within bounds, otherwise nearest bound  
- `OfArray`: Returns array filled with zeros
- `OfNamedTuple`: Recursively generates zero values for all fields
- `OfConstantWrapper`: Not supported (throws error)

# Examples
```julia
# Unbounded types
zero(of(Float64))           # 0.0
zero(of(Int))               # 0
zero(of(Array, 3, 2))       # 3×2 matrix of zeros

# Bounded types respect bounds
zero(of(Real, 1.0, 2.0))    # 1.0 (lower bound since 0 is outside)
zero(of(Int, -10, -5))      # -5 (upper bound since 0 is outside)

# Named tuples
T = @of(x=of(Real), y=of(Array, 2, 2))
zero(T)  # (x=0.0, y=[0.0 0.0; 0.0 0.0])

# With resolved constants
T = @of(n=of(Int; constant=true), data=of(Array, n, n))
zero(of(T; n=3))  # (data = 3×3 zero matrix)
```

# Errors
- Throws error for types with unresolved symbolic dimensions
- Throws error for constant wrapper types

# See also
[`rand`](@ref), [`of`](@ref)
"""
function Base.zero(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot create zero array with symbolic dimensions. Use zero(T; kwargs...) with dimension values.",
        )
    end
    return zeros(T, dims...)
end

function Base.zero(::Type{OfReal{T,L,U}}) where {T,L,U}
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && lower > 0
        return T(lower)
    elseif !isnothing(upper) && upper < 0
        return T(upper)
    else
        return zero(T)
    end
end

function Base.zero(::Type{OfInt{L,U}}) where {L,U}
    lower = type_to_bound(L)
    upper = type_to_bound(U)

    if !isnothing(lower) && lower > 0
        return lower
    elseif !isnothing(upper) && upper < 0
        return upper
    else
        return 0
    end
end

function Base.zero(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(zero(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

function Base.zero(::Type{OfConstantWrapper{T}}) where {T}
    return error(
        "Cannot generate zero values for constants. Use zero(of(T; const_name=value)) after providing the constant value.",
    )
end

# Unflatten with missing - documented in main unflatten docstring
function unflatten(::Type{T}, ::Missing) where {T<:OfType}
    if has_symbolic_dims(T)
        error(
            "Cannot unflatten type with symbolic dimensions or constants. Use unflatten(T, missing; kwargs...) with constant values.",
        )
    end
    return _unflatten_impl(T, missing)
end

# ========================================================================
# Size and Length Operations
# ========================================================================

"""
    size(::Type{T}) where T<:OfType

Get the dimensions/shape of an `OfType` specification.

Returns the size information encoded in the type. For arrays, returns a tuple
of dimensions. For scalars, returns an empty tuple. For named tuples, returns
a named tuple with the size of each field.

# Returns
- `OfArray`: Tuple of dimensions
- `OfReal`, `OfInt`: Empty tuple `()`
- `OfNamedTuple`: Named tuple with sizes of each field
- `OfConstantWrapper`: Delegates to wrapped type

# Examples
```julia
size(of(Array, 3, 4))        # (3, 4)
size(of(Float64))            # ()
size(of(Int, 0, 10))         # ()

T = @of(x=of(Real), y=of(Array, 2, 3))
size(T)                      # (x=(), y=(2, 3))
```

# Errors
- Throws error for arrays with unresolved symbolic dimensions

# See also
[`length`](@ref), [`of`](@ref)
"""
function Base.size(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error("Cannot get size of array with symbolic dimensions.")
    end
    return dims
end

function Base.size(::Type{OfReal{T,L,U}}) where {T,L,U}
    return ()  # Scalar has empty dimensions
end

function Base.size(::Type{OfInt{L,U}}) where {L,U}
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

function Base.size(::Type{OfConstantWrapper{T}}) where {T}
    return size(T)  # Delegate to wrapped type
end

"""
    length(::Type{T}) where T<:OfType

Get the total number of elements when the type is flattened.

Returns the total count of numerical values that would be in a flattened
representation. Arrays contribute their total element count, scalars 
contribute 1, and named tuples sum the lengths of all fields. Constants
(wrapped in `OfConstantWrapper`) contribute 0 as they are not part of 
the flattened representation.

# Returns
- `OfArray`: Product of dimensions (total elements)
- `OfReal`, `OfInt`: 1
- `OfNamedTuple`: Sum of lengths of all fields
- `OfConstantWrapper`: 0 (constants excluded from flattening)

# Examples
```julia
length(of(Array, 3, 4))      # 12
length(of(Float64))          # 1
length(of(Int, 0, 10))       # 1

T = @of(x=of(Real), y=of(Array, 2, 3))
length(T)                    # 7 (1 + 6)

# Constants don't count
T2 = @of(n=of(Int; constant=true), data=of(Array, 3, 3))
length(T2)                   # 0 (constant excluded)
length(of(T2; n=5))          # 9 (after resolving constant)
```

# Errors
- Throws error for arrays with unresolved symbolic dimensions

# See also
[`size`](@ref), [`flatten`](@ref), [`unflatten`](@ref)
"""
function Base.length(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error("Cannot get length of array with symbolic dimensions.")
    end
    return prod(dims)
end

function Base.length(::Type{OfReal{T,L,U}}) where {T,L,U}
    return 1
end

function Base.length(::Type{OfInt{L,U}}) where {L,U}
    return 1
end

function Base.length(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Sum lengths of all fields
    return sum(length(Types.parameters[i]) for i in 1:length(Names))
end

function Base.length(::Type{OfConstantWrapper{T}}) where {T}
    return 0  # Constants are not part of the flattened representation
end

# ========================================================================
# Symbolic Dimension Checking and Symbol Collection
# ========================================================================

# Check if a type has symbolic dimensions or constants
function has_symbolic_dims(::Type{T}) where {T<:OfType}
    if T <: OfArray
        dims = get_dims(T)
        return any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
    elseif T <: OfNamedTuple
        types = get_types(T)
        for i in 1:length(types.parameters)
            field_type = types.parameters[i]
            if field_type <: OfConstantWrapper || has_symbolic_dims(field_type)
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
                elseif d isa Type && d <: SymbolicExpr
                    # Extract symbols from expression
                    expr = d.parameters[1]
                    extract_symbols_from_expr(expr)
                end
            end
        elseif oft_type <: OfNamedTuple
            names = get_names(oft_type)
            types = get_types(oft_type)
            for (i, name) in enumerate(names)
                field_type = types.parameters[i]
                new_path = isempty(path) ? string(name) : "$path.$name"
                if field_type <: OfConstantWrapper
                    push!(symbols, name)
                else
                    collect_symbols(field_type, new_path)
                end
            end
        end
    end

    function extract_symbols_from_expr(expr::Tuple)
        for arg in expr[2:end]  # Skip operator
            if arg isa Symbol
                push!(symbols, arg)
            elseif arg isa Tuple
                extract_symbols_from_expr(arg)
            end
        end
    end

    collect_symbols(T)
    return unique(symbols)
end

# ========================================================================
# Validation Helper Functions
# ========================================================================

# Validate that a value is within bounds
function validate_bounds(value, lower, upper, type_name)
    if !isnothing(lower) && value < lower
        error("$type_name value $value is below lower bound $lower")
    end
    if !isnothing(upper) && value > upper
        error("$type_name value $value is above upper bound $upper")
    end
end

# ========================================================================
# Validation Functions
# ========================================================================

# Validation function - separate from type concretization
function _validate(::Type{T}, value) where {T<:OfType}
    if is_leaf(T)
        return _validate_leaf(T, value)
    else
        return _validate_container(T, value)
    end
end

function _validate_leaf(::Type{OfArray{T,N,D}}, value) where {T,N,D}
    value isa AbstractArray || error("Expected Array for OfArray, got $(typeof(value))")

    dims = get_dims(OfArray{T,N,D})
    any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims) && error(
        "Cannot validate array with symbolic dimensions. Use the parameterized constructor.",
    )

    # Check dimensions before conversion
    ndims(value) == N ||
        error("Array dimension mismatch: expected $N dimensions, got $(ndims(value))")
    size(value) == Tuple(dims) ||
        error("Array size mismatch: expected $(Tuple(dims)), got $(size(value))")

    arr = convert(Array{T,N}, value)
    return arr
end

function _validate_leaf(::Type{OfReal{T,L,U}}, value) where {T,L,U}
    if value isa Real
        val = convert(T, value)
        lower = type_to_bound(L)
        upper = type_to_bound(U)
        validate_bounds(val, lower, upper, "Real")
        return val
    else
        error("Expected Real for OfReal, got $(typeof(value))")
    end
end

function _validate_leaf(::Type{OfInt{L,U}}, value) where {L,U}
    if value isa Integer
        val = convert(Int, value)
        lower = type_to_bound(L)
        upper = type_to_bound(U)
        validate_bounds(val, lower, upper, "Int")
        return val
    elseif value isa Real
        # Allow conversion from Real to Int if it's a whole number
        if isinteger(value)
            return _validate_leaf(OfInt{L,U}, Int(value))
        else
            error("Expected Integer for OfInt, got non-integer Real: $value")
        end
    else
        error("Expected Integer for OfInt, got $(typeof(value))")
    end
end

function _validate_container(::Type{OfNamedTuple{Names,Types}}, value) where {Names,Types}
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
        _validate(field_type, getproperty(value, field_name))
    end
    return NamedTuple{Names}(vals)
end

function _validate_leaf(::Type{OfConstantWrapper{T}}, value) where {T}
    # Validate against the wrapped type
    return _validate_leaf(T, value)
end

# ========================================================================
# Flatten and Unflatten Operations  
# ========================================================================

"""
    flatten(::Type{T}, values) where T<:OfType

Convert structured values to a flat vector of numerical values.

Takes values matching an `OfType` specification and extracts all numerical 
values into a flat vector. This is useful for optimization routines that 
require a flat parameter vector. Arrays are vectorized, scalars are included
as single values, and named tuples are recursively flattened. Constants
(wrapped in `OfConstantWrapper`) are excluded.

# Arguments
- `T<:OfType`: The type specification
- `values`: Values matching the type specification

# Returns
A `Vector{Real}` containing all numerical values in order.

# Examples
```julia
# Simple types
flatten(of(Float64), 3.14)           # [3.14]
flatten(of(Array, 2, 2), [1 2; 3 4]) # [1.0, 3.0, 2.0, 4.0]

# Named tuples
T = @of(x=of(Real), y=of(Array, 2, 2))
values = (x=1.5, y=[1 2; 3 4])
flatten(T, values)  # [1.5, 1.0, 3.0, 2.0, 4.0]

# Constants excluded
T2 = @of(n=of(Int; constant=true), data=of(Array, 2, 2))
ConcreteT = of(T2; n=3)
flatten(ConcreteT, (data=[1 2; 3 4]))  # [1.0, 3.0, 2.0, 4.0]
```

# Errors
- Throws error if values don't match the type specification
- Throws error for types with unresolved symbolic dimensions

# See also
[`unflatten`](@ref), [`length`](@ref)
"""
function flatten(::Type{T}, values) where {T<:OfType}
    return _flatten_impl(T, values)
end

# Internal implementation for flatten
function _flatten_impl(::Type{T}, values) where {T<:OfType}
    # Check for symbolic dimensions
    if has_symbolic_dims(T)
        error(
            "Cannot flatten type with symbolic dimensions or constants. Use flatten(T, values; kwargs...) with constant values.",
        )
    end

    # First validate the values match the specification
    validated = _validate(T, values)

    # Extract all numerical values in order
    numerical_values = Real[]

    function walk_tree(oft_type::Type, val_node)
        if is_leaf(oft_type)
            if oft_type <: OfArray
                append!(numerical_values, vec(val_node))
            elseif oft_type <: OfReal
                push!(numerical_values, val_node)
            elseif oft_type <: OfInt
                push!(numerical_values, Float64(val_node))  # Convert to Float64 for flattening
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

"""
    unflatten(::Type{T}, flat_values::Vector{<:Real}) where T<:OfType
    unflatten(::Type{T}, ::Missing) where T<:OfType

Reconstruct structured values from a flat vector of numerical values.

Takes a flat vector produced by `flatten` and reconstructs the original 
structured values according to the type specification. This is the inverse
operation of `flatten`. Arrays are reshaped, scalars are extracted, and 
named tuples are recursively reconstructed. Bounds are validated during
reconstruction.

The second method with `missing` creates a structure with all values 
initialized to `missing`.

# Arguments
- `T<:OfType`: The type specification
- `flat_values`: Vector of numerical values in flattened order
- `missing`: Create structure with missing values

# Returns
Values matching the type specification structure.

# Examples
```julia
# Simple types
unflatten(of(Float64), [3.14])           # 3.14
unflatten(of(Array, 2, 2), [1, 3, 2, 4]) # [1 2; 3 4]

# Named tuples
T = @of(x=of(Real), y=of(Array, 2, 2))
flat = [1.5, 1.0, 3.0, 2.0, 4.0]
unflatten(T, flat)  # (x=1.5, y=[1.0 2.0; 3.0 4.0])

# With bounds validation
T2 = of(Real, 0, 1)
unflatten(T2, [0.5])  # 0.5
# unflatten(T2, [2.0])  # Error: value above upper bound

# Missing values
unflatten(T, missing)  # (x=missing, y=[missing missing; missing missing])
```

# Errors
- Throws error if wrong number of values provided
- Throws error if values violate bounds
- Throws error for types with unresolved symbolic dimensions

# See also
[`flatten`](@ref), [`length`](@ref)
"""
function unflatten(::Type{T}, flat_values::Vector{<:Real}) where {T<:OfType}
    return _unflatten_impl(T, flat_values)
end

# Internal implementation for unflatten
function _unflatten_impl(::Type{T}, flat_values::Vector{<:Real}) where {T<:OfType}
    # Check for symbolic dimensions
    if has_symbolic_dims(T)
        error(
            "Cannot unflatten type with symbolic dimensions or constants. Use unflatten(T, flat_values; kwargs...) with constant values.",
        )
    end

    pos = Ref(1)

    function reconstruct_node(oft_type::Type)
        if is_leaf(oft_type)
            if oft_type <: OfArray
                dims = size(oft_type)
                elem_type = get_element_type(oft_type)
                n_elements = prod(dims)
                if pos[] + n_elements - 1 > length(flat_values)
                    error("Not enough values in flat array")
                end
                values = flat_values[pos[]:(pos[] + n_elements - 1)]
                pos[] += n_elements
                # Convert to proper array type
                typed_array = Array{elem_type}(reshape(values, dims))
                return typed_array
            elseif oft_type <: OfReal
                if pos[] > length(flat_values)
                    error("Not enough values in flat array")
                end
                val = flat_values[pos[]]
                pos[] += 1

                # Apply bounds validation
                lower = type_to_bound(get_lower(oft_type))
                upper = type_to_bound(get_upper(oft_type))
                validate_bounds(val, lower, upper, "Real")
                return val
            elseif oft_type <: OfInt
                if pos[] > length(flat_values)
                    error("Not enough values in flat array")
                end
                val = flat_values[pos[]]
                pos[] += 1

                # Convert back to Int and apply bounds validation
                int_val = round(Int, val)
                lower = type_to_bound(get_lower(oft_type))
                upper = type_to_bound(get_upper(oft_type))
                validate_bounds(int_val, lower, upper, "Int")
                return int_val
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

# Internal implementation for unflatten with missing
function _unflatten_impl(::Type{T}, ::Missing) where {T<:OfType}
    function reconstruct_node(oft_type::Type)
        if is_leaf(oft_type)
            if oft_type <: OfArray
                dims = size(oft_type)
                return fill(missing, dims...)
            elseif oft_type <: OfReal || oft_type <: OfInt
                return missing
            end
        elseif oft_type <: OfNamedTuple
            names = get_names(oft_type)
            types = get_types(oft_type)
            values = Tuple(reconstruct_node(types.parameters[i]) for i in 1:length(names))
            return NamedTuple{names}(values)
        end
    end
    return reconstruct_node(T)
end

# ========================================================================
# Display Helper Functions
# ========================================================================

# Format a bound type for display
function format_bound(bound_type, constant_fields, use_color)
    if bound_type === Nothing
        return "nothing"
    elseif bound_type isa Real
        # Numeric values
        return string(bound_type)
    elseif bound_type isa Type && bound_type <: SymbolicRef
        sym = type_to_bound(bound_type)
        if sym in constant_fields && use_color
            return sprint() do io_inner
                printstyled(io_inner, string(sym); color=:cyan)
            end
        else
            return string(sym)
        end
    else
        return string(bound_type)
    end
end

# Show a bounded type (OfReal or OfInt) with proper formatting
function show_bounded_type(io::IO, type_name::String, L, U; constant::Bool=false)
    use_color = get(io, :color, false)
    constant_fields = get(io, :constant_fields, Symbol[])

    if L === Nothing && U === Nothing
        if constant
            if use_color
                printstyled(io, "of($type_name"; color=:cyan)
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:cyan)
            else
                print(io, "of($type_name; constant=true)")
            end
        else
            print(io, "of($type_name)")
        end
    else
        lower_str = format_bound(L, constant_fields, use_color)
        upper_str = format_bound(U, constant_fields, use_color)

        if constant && use_color
            printstyled(io, "of($type_name, "; color=:cyan)
            # Handle lower bound
            if L isa Type && L <: SymbolicRef && type_to_bound(L) in constant_fields
                printstyled(io, string(type_to_bound(L)); color=:cyan)
            else
                printstyled(io, lower_str; color=:cyan)
            end
            printstyled(io, ", "; color=:cyan)
            # Handle upper bound
            if U isa Type && U <: SymbolicRef && type_to_bound(U) in constant_fields
                printstyled(io, string(type_to_bound(U)); color=:cyan)
            else
                printstyled(io, upper_str; color=:cyan)
            end
            printstyled(io, "; constant=true"; color=:light_black)
            printstyled(io, ")"; color=:cyan)
        else
            print(io, "of($type_name, ")
            # Handle lower bound
            if L isa Type &&
                L <: SymbolicRef &&
                type_to_bound(L) in constant_fields &&
                use_color
                printstyled(io, string(type_to_bound(L)); color=:cyan)
            else
                print(io, lower_str)
            end
            print(io, ", ")
            # Handle upper bound
            if U isa Type &&
                U <: SymbolicRef &&
                type_to_bound(U) in constant_fields &&
                use_color
                printstyled(io, string(type_to_bound(U)); color=:cyan)
            else
                print(io, upper_str)
            end
            if constant
                print(io, "; constant=true")
            end
            print(io, ")")
        end
    end
end

# ========================================================================
# Display and Show Methods
# ========================================================================

# Helper to convert expression tuple back to string
function expr_tuple_to_string(expr::Tuple)
    if length(expr) < 2
        return string(expr)
    end

    op = expr[1]
    if op in (:+, :-, :*, :/) && length(expr) == 3
        # Format arguments
        arg1_str = format_expr_arg(expr[2])
        arg2_str = format_expr_arg(expr[3])

        # Add parentheses for multiplication and division if needed
        if op in (:*, :/) && expr[2] isa Tuple
            arg1_str = "($arg1_str)"
        end
        if op in (:*, :/) && expr[3] isa Tuple
            arg2_str = "($arg2_str)"
        end

        return "$arg1_str $op $arg2_str"
    else
        return string(expr)
    end
end

# Format a single expression argument
function format_expr_arg(arg)
    if arg isa Symbol
        string(arg)
    elseif arg isa Tuple
        expr_tuple_to_string(arg)
    else
        string(arg)
    end
end

# Show implementations
function Base.show(io::IO, ::Type{OfArray{T,N,D}}) where {T,N,D}
    # Check if we're in a context where we can highlight symbolic references
    use_color = get(io, :color, false)
    constant_fields = get(io, :constant_fields, Symbol[])

    # Process dimensions, highlighting those that reference constants
    if use_color && !isempty(constant_fields)
        # We need to manually handle the coloring
        print(io, "of(Array, ")
        if T !== Float64
            print(io, T, ", ")
        end
        # D is a Tuple type, so we need to access its parameters
        dims_list = get_dims(OfArray{T,N,D})
        for (i, d) in enumerate(dims_list)
            if d isa Symbol && d in constant_fields
                # This dimension references a constant field - highlight it
                printstyled(io, string(d); color=:cyan)
            elseif d isa Type && d <: SymbolicExpr
                # This is an expression - format it nicely
                expr = d.parameters[1]
                expr_str = expr_tuple_to_string(expr)
                # Check if any symbols in the expression are constants
                has_constant = false
                function check_expr(e::Tuple)
                    for arg in e[2:end]
                        if arg isa Symbol && arg in constant_fields
                            has_constant = true
                        elseif arg isa Tuple
                            check_expr(arg)
                        end
                    end
                end
                check_expr(expr)
                if has_constant
                    printstyled(io, expr_str; color=:cyan)
                else
                    print(io, expr_str)
                end
            else
                print(io, string(d))
            end
            if i < length(dims_list)
                print(io, ", ")
            end
        end
        print(io, ")")
        return nothing
    end

    # Non-color version
    # D is a Tuple type, so we need to access its parameters
    dims_list = get_dims(OfArray{T,N,D})
    dims_str = join(
        map(dims_list) do d
            if d isa Type && d <: SymbolicExpr
                expr = d.parameters[1]
                expr_tuple_to_string(expr)
            else
                string(d)
            end
        end,
        ", ",
    )

    if T === Float64
        print(io, "of(Array, ", dims_str, ")")
    else
        print(io, "of(Array, ", T, ", ", dims_str, ")")
    end
end

function Base.show(io::IO, ::Type{OfReal{T,L,U}}) where {T,L,U}
    # Show the specific float type instead of generic "Real"
    type_name = string(T)
    return show_bounded_type(io, type_name, L, U)
end

function Base.show(io::IO, ::Type{OfInt{L,U}}) where {L,U}
    return show_bounded_type(io, "Int", L, U)
end

# Helper function to collect constant fields from a NamedTuple type
function _collect_constant_fields(Names, Types)
    constant_fields = Symbol[]
    for (name, T) in zip(Names, Types.parameters)
        if T <: OfConstantWrapper
            push!(constant_fields, name)
        end
    end
    return constant_fields
end

# Helper function to estimate output length for a NamedTuple type
function _estimate_namedtuple_length(Names, Types)
    total_length = 4  # "@of("
    for (name, T) in zip(Names, Types.parameters)
        total_length += length(string(name)) + 1  # name=
        # Rough estimate of type string length
        if T <: OfArray
            dims = get_dims(T)
            total_length += 15 + sum(d -> length(string(d)), dims; init=0)
        else
            total_length += 20
        end
        total_length += 2  # ", "
    end
    return total_length
end

# Helper function to show a field with appropriate styling
function _show_field_type(io::IO, T::Type, is_constant::Bool)
    if is_constant && get(io, :color, false)
        wrapped = get_wrapped_type(T)
        if wrapped <: OfReal &&
            get_lower(wrapped) === Nothing &&
            get_upper(wrapped) === Nothing
            elem_type = get_element_type(wrapped)
            type_name = elem_type === Float64 ? "Real" : string(elem_type)
            printstyled(io, "of($type_name"; color=:cyan)
            printstyled(io, "; constant=true"; color=:light_black)
            printstyled(io, ")"; color=:cyan)
        elseif wrapped <: OfInt &&
            get_lower(wrapped) === Nothing &&
            get_upper(wrapped) === Nothing
            printstyled(io, "of(Int"; color=:cyan)
            printstyled(io, "; constant=true"; color=:light_black)
            printstyled(io, ")"; color=:cyan)
        else
            show(io, T)
        end
    else
        show(io, T)
    end
end

# Helper function to print a single field in NamedTuple
function _print_namedtuple_field(
    io::IO, name::Symbol, T::Type, is_constant::Bool, separator::String
)
    if is_constant && get(io, :color, false)
        printstyled(io, name; color=:cyan, bold=true)
    else
        print(io, name)
    end

    print(io, separator)
    _show_field_type(io, T, is_constant)
end

function Base.show(io::IO, ::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Collect constant fields to pass to child types
    constant_fields = _collect_constant_fields(Names, Types)
    io_with_constants = IOContext(io, :constant_fields => constant_fields)

    # Determine if we should use multi-line format
    compact = get(io, :compact, false)
    multiline = !compact && length(Names) > 3

    # Check if single-line output would be too long
    if !multiline && !compact
        multiline = _estimate_namedtuple_length(Names, Types) > 80
    end

    print(io, "@of(")

    if multiline
        println(io)
        for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
            print(io, "    ")
            is_constant = T <: OfConstantWrapper
            _print_namedtuple_field(io_with_constants, name, T, is_constant, " = ")

            if i < length(Names)
                println(io, ",")
            else
                println(io)
            end
        end
        print(io, ")")
    else
        # Single line format
        for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
            is_constant = T <: OfConstantWrapper
            _print_namedtuple_field(io_with_constants, name, T, is_constant, "=")

            if i < length(Names)
                print(io, ", ")
            end
        end
        print(io, ")")
    end
end

function Base.show(io::IO, ::Type{OfConstantWrapper{T}}) where {T}
    # Show the wrapped type with constant=true
    if T <: OfReal
        elem_type = get_element_type(T)
        # Use "Real" for backward compatibility when Float64 is the element type
        type_name = elem_type === Float64 ? "Real" : string(elem_type)
        show_bounded_type(io, type_name, get_lower(T), get_upper(T); constant=true)
    elseif T <: OfInt
        show_bounded_type(io, "Int", get_lower(T), get_upper(T); constant=true)
    elseif T <: OfArray
        # This case should not happen since constant=true is not allowed for Arrays
        # But if it does, show it as a fallback
        print(io, "OfConstantWrapper{", T, "}")
        printstyled(io, " # Invalid: constant=true not supported for Arrays"; color=:red)
    else
        # Fallback
        print(io, "OfConstantWrapper{", T, "}")
    end
end
