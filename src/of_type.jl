using Random: randexp

# Abstract base type for all Of types
abstract type OfType end

# Wrapper type for symbolic references in bounds
struct SymbolicRef{S} end

# Parametric types that store specification in type parameters
struct OfReal{Lower,Upper} <: OfType
    function OfReal{L,U}() where {L,U}
        return error(
            "OfReal is a type specification, not an instantiable object. Use of(Real, ...) to create the type.",
        )
    end
end

struct OfInt{Lower,Upper} <: OfType
    function OfInt{L,U}() where {L,U}
        return error(
            "OfInt is a type specification, not an instantiable object. Use of(Int, ...) to create the type.",
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

struct OfConstantWrapper{T<:OfType} <: OfType
    function OfConstantWrapper{T}() where {T<:OfType}
        return error(
            "OfConstantWrapper is a type specification, not an instantiable object. Use of(...; constant=true) to create the type.",
        )
    end
end

# Helper functions to extract type parameters
get_lower(::Type{OfReal{L,U}}) where {L,U} = L
get_upper(::Type{OfReal{L,U}}) where {L,U} = U
get_lower(::Type{OfInt{L,U}}) where {L,U} = L
get_upper(::Type{OfInt{L,U}}) where {L,U} = U
get_element_type(::Type{OfArray{T,N,D}}) where {T,N,D} = T
get_ndims(::Type{OfArray{T,N,D}}) where {T,N,D} = N
get_dims(::Type{OfArray{T,N,D}}) where {T,N,D} = D
get_names(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Names
get_types(::Type{OfNamedTuple{Names,Types}}) where {Names,Types} = Types
get_wrapped_type(::Type{OfConstantWrapper{T}}) where {T} = T

# Check if a type is a leaf
is_leaf(::Type{<:OfArray}) = true
is_leaf(::Type{<:OfReal}) = true
is_leaf(::Type{<:OfInt}) = true
is_leaf(::Type{<:OfNamedTuple}) = false
is_leaf(::Type{<:OfConstantWrapper}) = true

# Convert bounds to type parameters
bound_to_type(::Nothing) = Nothing
bound_to_type(x::Real) = Val{x}
bound_to_type(s::Symbol) = SymbolicRef{s}
bound_to_type(s::QuoteNode) = SymbolicRef{s.value}

# Extract value from Val type
type_to_bound(::Type{Nothing}) = nothing
type_to_bound(::Type{Val{x}}) where {x} = x
type_to_bound(::Type{SymbolicRef{S}}) where {S} = S
type_to_bound(s::Symbol) = s

# Resolve bound references during type concretization
function resolve_bound(::Type{Nothing}, replacements::NamedTuple)
    return Nothing
end

function resolve_bound(::Type{Val{x}}, replacements::NamedTuple) where {x}
    return Val{x}
end

function resolve_bound(::Type{SymbolicRef{S}}, replacements::NamedTuple) where {S}
    if haskey(replacements, S)
        return bound_to_type(replacements[S])
    else
        return SymbolicRef{S}
    end
end

function resolve_bound(T::Type, ::NamedTuple)
    return T
end

# Constructor functions for creating Of types
function of(::Type{Array}, dims...; constant::Bool=false)
    if constant
        error("constant=true is only supported for Int and Real types, not Array")
    end
    # Default to Float64 for unspecified array types
    processed_dims = map(dims) do d
        if d isa QuoteNode
            d.value
        else
            d
        end
    end
    return OfArray{Float64,length(processed_dims),processed_dims}
end

function of(::Type{Array}, T::Type, dims...; constant::Bool=false)
    if constant
        error("constant=true is only supported for Int and Real types, not Array")
    end
    processed_dims = map(dims) do d
        if d isa QuoteNode
            d.value
        else
            d
        end
    end
    return OfArray{T,length(processed_dims),processed_dims}
end

function of(::Type{Int}; constant::Bool=false)
    base_type = OfInt{Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{Int},
    lower::Union{Int,Nothing,Symbol},
    upper::Union{Int,Nothing,Symbol};
    constant::Bool=false,
)
    L = bound_to_type(lower)
    U = bound_to_type(upper)
    base_type = OfInt{L,U}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(::Type{Real}; constant::Bool=false)
    base_type = OfReal{Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{Real},
    lower::Union{Real,Nothing,Symbol},
    upper::Union{Real,Nothing,Symbol};
    constant::Bool=false,
)
    L = bound_to_type(lower)
    U = bound_to_type(upper)
    base_type = OfReal{L,U}
    return constant ? OfConstantWrapper{base_type} : base_type
end

# Infer OfType from concrete values
function of(::Real)
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

# Type concretization functions
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

        if field_type <: OfConstantWrapper && haskey(replacements, name)
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
        elseif field_type <: OfReal
            # Check if bounds have symbolic references
            lower = get_lower(field_type)
            upper = get_upper(field_type)

            new_lower = resolve_bound(lower, replacements)
            new_upper = resolve_bound(upper, replacements)

            if new_lower !== lower || new_upper !== upper
                # Create new type with resolved bounds
                return OfReal{new_lower,new_upper}
            else
                return field_type
            end
        elseif field_type <: OfInt
            # Check if bounds have symbolic references
            lower = get_lower(field_type)
            upper = get_upper(field_type)

            new_lower = resolve_bound(lower, replacements)
            new_upper = resolve_bound(upper, replacements)

            if new_lower !== lower || new_upper !== upper
                # Create new type with resolved bounds
                return OfInt{new_lower,new_upper}
            else
                return field_type
            end
        elseif field_type <: OfConstantWrapper
            # Handle wrapped types - even constants might have symbolic bounds
            wrapped = get_wrapped_type(field_type)
            if wrapped <: OfReal
                # Check if the wrapped real has symbolic bounds
                lower = get_lower(wrapped)
                upper = get_upper(wrapped)

                new_lower = resolve_bound(lower, replacements)
                new_upper = resolve_bound(upper, replacements)

                if new_lower !== lower || new_upper !== upper
                    # Create new wrapped type with resolved bounds
                    return OfConstantWrapper{OfReal{new_lower,new_upper}}
                else
                    return field_type
                end
            elseif wrapped <: OfInt
                # Check if the wrapped int has symbolic bounds
                lower = get_lower(wrapped)
                upper = get_upper(wrapped)

                new_lower = resolve_bound(lower, replacements)
                new_upper = resolve_bound(upper, replacements)

                if new_lower !== lower || new_upper !== upper
                    # Create new wrapped type with resolved bounds
                    return OfConstantWrapper{OfInt{new_lower,new_upper}}
                else
                    return field_type
                end
            else
                # For other wrapped types, keep as is
                return field_type
            end
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
    # For other types (OfReal, OfConstantWrapper), just return as-is
    return T
end

# Constructor with keyword arguments - concretizes types and optionally validates
function (::Type{T})(; kwargs...) where {T<:OfType}
    if T <: OfNamedTuple
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

        # First concretize with constants
        concrete_type = of(T, NamedTuple(constants))

        # If values were provided, validate them against the concrete type
        if !isempty(values)
            # Check if all constants are resolved
            if has_symbolic_dims(concrete_type)
                missing_symbols = get_unresolved_symbols(concrete_type)
                error(
                    "Missing values for symbolic dimensions: $(join(missing_symbols, ", "))"
                )
            end

            # Validate the values match the concrete type structure
            concrete_names = get_names(concrete_type)
            concrete_types = get_types(concrete_type)

            for name in concrete_names
                if haskey(values, name)
                    idx = findfirst(==(name), concrete_names)
                    field_type = concrete_types.parameters[idx]

                    # Validate the value matches the expected type
                    try
                        _validate(field_type, values[name])
                    catch e
                        error("Validation failed for field $name: $(e.msg)")
                    end
                else
                    error("Missing value for field: $name when validating")
                end
            end
        end

        return concrete_type
    else
        # For non-NamedTuple types, just concretize
        return of(T, NamedTuple(kwargs))
    end
end

"""
    @of(field1=spec1, field2=spec2, ...)

Create an OfNamedTuple type with cleaner syntax that allows direct references
between fields without needing symbols.

# Examples
```julia
# Instead of:
T = of((
    rows=of(Constant),
    cols=of(Constant),
    data=of(Array, :rows, :cols)
))

# You can write:
T = @of(
    rows=of(Int; constant=true),
    cols=of(Int; constant=true),
    data=of(Array, rows, cols)
)
```
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

# Process an expression, converting field references to symbols in expressions
function process_expression_refs(expr::Expr, available_fields::Vector{Symbol})
    # For simple arithmetic expressions with field references
    if expr.head in [:+, :-, :*, :/, :call]
        new_args = []

        for arg in expr.args
            if arg isa Symbol && arg in available_fields
                # This is a field reference in an expression
                # We need to keep the expression structure but mark it
                push!(new_args, arg)
            elseif arg isa Expr
                push!(new_args, process_expression_refs(arg, available_fields))
            else
                push!(new_args, arg)
            end
        end

        # For expressions like `rows + 1`, we need to return the whole expression
        # as a quoted expression that will be stored in the type
        if any(arg isa Symbol && arg in available_fields for arg in expr.args)
            # This expression contains field references, quote the whole thing
            return QuoteNode(expr)
        else
            return Expr(expr.head, new_args...)
        end
    else
        return expr
    end
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
        "Cannot generate random values for constants. Use rand(T; const_name=value) to provide the constant value.",
    )
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
        "Cannot generate zero values for constants. Use zero(T; const_name=value) to provide the constant value.",
    )
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

# Check if a type has symbolic dimensions or constants
function has_symbolic_dims(::Type{T}) where {T<:OfType}
    if T <: OfArray
        dims = get_dims(T)
        return any(d -> d isa Symbol, dims)
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

    collect_symbols(T)
    return unique(symbols)
end

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

function _validate_leaf(::Type{OfReal{L,U}}, value) where {L,U}
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

function _validate_leaf(::Type{OfInt{L,U}}, value) where {L,U}
    if value isa Integer
        val = convert(Int, value)
        lower = type_to_bound(L)
        upper = type_to_bound(U)

        if !isnothing(lower) && val < lower
            error("Value $val is below lower bound $lower")
        end
        if !isnothing(upper) && val > upper
            error("Value $val is above upper bound $upper")
        end
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

# Flatten implementation for types
function flatten(::Type{T}, values) where {T<:OfType}
    # Check for symbolic dimensions
    if has_symbolic_dims(T)
        error(
            "Cannot flatten type with symbolic dimensions or constants. Use of(T, rows=3, cols=4) to create a concrete type first.",
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

                if !isnothing(lower) && val < lower
                    error("Value $val is below lower bound $lower")
                end
                if !isnothing(upper) && val > upper
                    error("Value $val is above upper bound $upper")
                end
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

                if !isnothing(lower) && int_val < lower
                    error("Value $int_val is below lower bound $lower")
                end
                if !isnothing(upper) && int_val > upper
                    error("Value $int_val is above upper bound $upper")
                end
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
        for (i, d) in enumerate(D)
            if d isa Symbol && d in constant_fields
                # This dimension references a constant field - highlight it
                printstyled(io, string(d); color=:yellow)
            else
                print(io, string(d))
            end
            if i < length(D)
                print(io, ", ")
            end
        end
        print(io, ")")
        return nothing
    end

    # Non-color version
    dims_str = join(map(d -> string(d), D), ", ")

    if T === Float64
        print(io, "of(Array, ", dims_str, ")")
    else
        print(io, "of(Array, ", T, ", ", dims_str, ")")
    end
end

function Base.show(io::IO, ::Type{OfReal{L,U}}) where {L,U}
    if isnothing(L) && isnothing(U)
        print(io, "of(Real)")
    else
        use_color = get(io, :color, false)
        constant_fields = get(io, :constant_fields, Symbol[])

        # Handle different bound types
        lower_str = if L === Nothing
            "nothing"
        elseif L <: Val
            string(type_to_bound(L))
        elseif L <: SymbolicRef
            sym = type_to_bound(L)
            if sym in constant_fields && use_color
                sprint() do io_inner
                    printstyled(io_inner, string(sym); color=:yellow)
                end
            else
                string(sym)
            end
        else
            string(L)
        end

        upper_str = if U === Nothing
            "nothing"
        elseif U <: Val
            string(type_to_bound(U))
        elseif U <: SymbolicRef
            sym = type_to_bound(U)
            if sym in constant_fields && use_color
                sprint() do io_inner
                    printstyled(io_inner, string(sym); color=:yellow)
                end
            else
                string(sym)
            end
        else
            string(U)
        end

        print(io, "of(Real, ")
        # Handle lower bound
        if L <: SymbolicRef && type_to_bound(L) in constant_fields && use_color
            printstyled(io, string(type_to_bound(L)); color=:yellow)
        else
            print(io, lower_str)
        end
        print(io, ", ")
        # Handle upper bound
        if U <: SymbolicRef && type_to_bound(U) in constant_fields && use_color
            printstyled(io, string(type_to_bound(U)); color=:yellow)
        else
            print(io, upper_str)
        end
        print(io, ")")
    end
end

function Base.show(io::IO, ::Type{OfInt{L,U}}) where {L,U}
    if isnothing(L) && isnothing(U)
        print(io, "of(Int)")
    else
        use_color = get(io, :color, false)
        constant_fields = get(io, :constant_fields, Symbol[])

        # Handle different bound types
        lower_str = if L === Nothing
            "nothing"
        elseif L <: Val
            string(type_to_bound(L))
        elseif L <: SymbolicRef
            sym = type_to_bound(L)
            if sym in constant_fields && use_color
                sprint() do io_inner
                    printstyled(io_inner, string(sym); color=:yellow)
                end
            else
                string(sym)
            end
        else
            string(L)
        end

        upper_str = if U === Nothing
            "nothing"
        elseif U <: Val
            string(type_to_bound(U))
        elseif U <: SymbolicRef
            sym = type_to_bound(U)
            if sym in constant_fields && use_color
                sprint() do io_inner
                    printstyled(io_inner, string(sym); color=:yellow)
                end
            else
                string(sym)
            end
        else
            string(U)
        end

        print(io, "of(Int, ")
        # Handle lower bound
        if L <: SymbolicRef && type_to_bound(L) in constant_fields && use_color
            printstyled(io, string(type_to_bound(L)); color=:yellow)
        else
            print(io, lower_str)
        end
        print(io, ", ")
        # Handle upper bound
        if U <: SymbolicRef && type_to_bound(U) in constant_fields && use_color
            printstyled(io, string(type_to_bound(U)); color=:yellow)
        else
            print(io, upper_str)
        end
        print(io, ")")
    end
end

function Base.show(io::IO, ::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    # Collect constant fields to pass to child types
    constant_fields = Symbol[]
    for (name, T) in zip(Names, Types.parameters)
        if T <: OfConstantWrapper
            push!(constant_fields, name)
        end
    end

    # Create a new IO context with constant fields information
    io_with_constants = IOContext(io, :constant_fields => constant_fields)

    print(io, "@of(")
    for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
        # Check if this field is a constant
        is_constant = T <: OfConstantWrapper

        if is_constant && get(io, :color, false)
            # Print constant fields in yellow
            printstyled(io, name; color=:yellow, bold=true)
        else
            print(io, name)
        end

        print(io, "=")

        # For constants, show the wrapped type with styling
        if is_constant && get(io, :color, false)
            # Show the wrapped type content
            wrapped = get_wrapped_type(T)
            if wrapped <: OfReal &&
                get_lower(wrapped) === Nothing &&
                get_upper(wrapped) === Nothing
                printstyled(io, "of(Real"; color=:yellow)
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            elseif wrapped <: OfInt &&
                get_lower(wrapped) === Nothing &&
                get_upper(wrapped) === Nothing
                printstyled(io, "of(Int"; color=:yellow)
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            else
                # For other constant types, use default show with constants context
                show(io_with_constants, T)
            end
        else
            # Show non-constant fields with the constants context
            show(io_with_constants, T)
        end

        if i < length(Names)
            print(io, ", ")
        end
    end
    return print(io, ")")
end

function Base.show(io::IO, ::Type{OfConstantWrapper{T}}) where {T}
    # Show the wrapped type with constant=true
    # Extract the base specification
    use_color = get(io, :color, false)

    if T <: OfReal
        L = get_lower(T)
        U = get_upper(T)
        if L === Nothing && U === Nothing
            if use_color
                printstyled(io, "of(Real"; color=:yellow)
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            else
                print(io, "of(Real; constant=true)")
            end
        else
            # Get constant fields from context
            constant_fields = get(io, :constant_fields, Symbol[])

            # Handle different bound types
            lower_str = if L === Nothing
                "nothing"
            elseif L <: Val
                string(type_to_bound(L))
            elseif L <: SymbolicRef
                sym = type_to_bound(L)
                if sym in constant_fields && use_color
                    sprint() do io_inner
                        printstyled(io_inner, string(sym); color=:yellow)
                    end
                else
                    string(sym)
                end
            else
                string(L)
            end

            upper_str = if U === Nothing
                "nothing"
            elseif U <: Val
                string(type_to_bound(U))
            elseif U <: SymbolicRef
                sym = type_to_bound(U)
                if sym in constant_fields && use_color
                    sprint() do io_inner
                        printstyled(io_inner, string(sym); color=:yellow)
                    end
                else
                    string(sym)
                end
            else
                string(U)
            end

            if use_color
                printstyled(io, "of(Real, "; color=:yellow)
                # Handle lower bound
                if L <: SymbolicRef && type_to_bound(L) in constant_fields
                    printstyled(io, string(type_to_bound(L)); color=:yellow)
                else
                    printstyled(io, lower_str; color=:yellow)
                end
                printstyled(io, ", "; color=:yellow)
                # Handle upper bound
                if U <: SymbolicRef && type_to_bound(U) in constant_fields
                    printstyled(io, string(type_to_bound(U)); color=:yellow)
                else
                    printstyled(io, upper_str; color=:yellow)
                end
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            else
                print(io, "of(Real, ", lower_str, ", ", upper_str, "; constant=true)")
            end
        end
    elseif T <: OfInt
        L = get_lower(T)
        U = get_upper(T)
        if L === Nothing && U === Nothing
            if use_color
                printstyled(io, "of(Int"; color=:yellow)
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            else
                print(io, "of(Int; constant=true)")
            end
        else
            # Get constant fields from context
            constant_fields = get(io, :constant_fields, Symbol[])

            # Handle different bound types
            lower_str = if L === Nothing
                "nothing"
            elseif L <: Val
                string(type_to_bound(L))
            elseif L <: SymbolicRef
                sym = type_to_bound(L)
                if sym in constant_fields && use_color
                    sprint() do io_inner
                        printstyled(io_inner, string(sym); color=:yellow)
                    end
                else
                    string(sym)
                end
            else
                string(L)
            end

            upper_str = if U === Nothing
                "nothing"
            elseif U <: Val
                string(type_to_bound(U))
            elseif U <: SymbolicRef
                sym = type_to_bound(U)
                if sym in constant_fields && use_color
                    sprint() do io_inner
                        printstyled(io_inner, string(sym); color=:yellow)
                    end
                else
                    string(sym)
                end
            else
                string(U)
            end

            if use_color
                printstyled(io, "of(Int, "; color=:yellow)
                # Handle lower bound
                if L <: SymbolicRef && type_to_bound(L) in constant_fields
                    printstyled(io, string(type_to_bound(L)); color=:yellow)
                else
                    printstyled(io, lower_str; color=:yellow)
                end
                printstyled(io, ", "; color=:yellow)
                # Handle upper bound
                if U <: SymbolicRef && type_to_bound(U) in constant_fields
                    printstyled(io, string(type_to_bound(U)); color=:yellow)
                else
                    printstyled(io, upper_str; color=:yellow)
                end
                printstyled(io, "; constant=true"; color=:light_black)
                printstyled(io, ")"; color=:yellow)
            else
                print(io, "of(Int, ", lower_str, ", ", upper_str, "; constant=true)")
            end
        end
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