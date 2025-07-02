using Random: randexp

# ========================================================================
# Core Type Definitions
# ========================================================================

# Abstract base type for all Of types
abstract type OfType end

# Wrapper type for symbolic references in bounds
struct SymbolicRef{S} end

# Wrapper type for symbolic expressions (e.g., b+1, 2*n)
struct SymbolicExpr{E} end

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

# ========================================================================
# Type Parameter Extraction Helpers
# ========================================================================
get_lower(::Type{OfReal{L,U}}) where {L,U} = L
get_upper(::Type{OfReal{L,U}}) where {L,U} = U
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
bound_to_type(x::Real) = Val{x}
bound_to_type(s::Symbol) = SymbolicRef{s}
bound_to_type(s::QuoteNode) = SymbolicRef{s.value}

# Extract value from Val type
type_to_bound(::Type{Nothing}) = nothing
type_to_bound(::Type{Val{x}}) where {x} = x
type_to_bound(::Type{SymbolicRef{S}}) where {S} = S
type_to_bound(s::Symbol) = s

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

function resolve_bound(::Type{SymbolicExpr{E}}, replacements::NamedTuple) where {E}
    # Evaluate the expression with current replacements
    evaluated = eval_symbolic_expr(E, replacements)
    return bound_to_type(evaluated)
end

function resolve_bound(T::Type, ::NamedTuple)
    return T
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
        lower  # Keep type parameters as-is
    else
        bound_to_type(lower)
    end
    U = if upper isa Type
        upper  # Keep type parameters as-is
    else
        bound_to_type(upper)
    end
    return L, U
end

# ========================================================================
# Constructor Functions
# ========================================================================
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

function of(::Type{Real}; constant::Bool=false)
    base_type = OfReal{Nothing,Nothing}
    return constant ? OfConstantWrapper{base_type} : base_type
end

function of(
    ::Type{Real},
    lower::Union{Real,Nothing,Symbol,Type},
    upper::Union{Real,Nothing,Symbol,Type};
    constant::Bool=false,
)
    L, U = process_bounds(lower, upper)
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

# Support for passing OfType types through of()
# (This is handled by the generic of functions below)

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
            return OfReal{new_lower,new_upper}
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
function of(::Type{T}, pairs::Pair{Symbol}...) where {T<:OfType}
    return of(T, NamedTuple(pairs))
end

function of(::Type{T}; kwargs...) where {T<:OfType}
    return of(T, NamedTuple(kwargs))
end

function of(::Type{OfNamedTuple{Names,Types}}, replacements::NamedTuple) where {Names,Types}
    # Replace OfConstants and symbolic dimensions with concrete values
    # Build lists for remaining fields (excluding resolved constants)
    remaining_names = Symbol[]
    remaining_types = []

    for i in 1:length(Names)
        name = Names[i]
        field_type = Types.parameters[i]

        if field_type <: OfConstantWrapper && haskey(replacements, name)
            # Skip this field - it's a constant that has been resolved
            continue
        elseif field_type <: OfArray
            # Check if array has symbolic dimensions
            dims = get_dims(field_type)
            new_dims = map(dims) do d
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
            if new_dims != dims
                # Create new array type with concrete dimensions
                T = get_element_type(field_type)
                push!(remaining_names, name)
                push!(remaining_types, of(Array, T, new_dims...))
            else
                push!(remaining_names, name)
                push!(remaining_types, field_type)
            end
        elseif field_type <: OfNamedTuple
            # Recursively handle nested named tuples
            push!(remaining_names, name)
            push!(remaining_types, of(field_type, replacements))
        elseif field_type <: OfReal || field_type <: OfInt
            # Check if bounds have symbolic references
            push!(remaining_names, name)
            push!(remaining_types, resolve_bounded_type(field_type, replacements))
        elseif field_type <: OfConstantWrapper
            # Handle wrapped types without replacement values - keep as constants
            wrapped = get_wrapped_type(field_type)
            resolved = resolve_bounded_type(wrapped, replacements)
            push!(remaining_names, name)
            if resolved !== wrapped
                # Wrap the resolved type back
                push!(remaining_types, OfConstantWrapper{resolved})
            else
                push!(remaining_types, field_type)
            end
        else
            push!(remaining_names, name)
            push!(remaining_types, field_type)
        end
    end

    # Create new NamedTuple type with only remaining fields
    if isempty(remaining_names)
        error("All fields were constants and have been resolved. No fields remain.")
    end

    return OfNamedTuple{Tuple(remaining_names),Tuple{remaining_types...}}
end

function of(::Type{OfArray{T,N,D}}, replacements::NamedTuple) where {T,N,D}
    # Replace symbolic dimensions in array types
    dims = get_dims(OfArray{T,N,D})
    new_dims = map(dims) do d
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
    return OfArray{T,N,Tuple{new_dims...}}
end

function of(::Type{T}, replacements::NamedTuple) where {T<:OfType}
    # For other types (OfReal, OfConstantWrapper), just return as-is
    return T
end

# ========================================================================
# Parameterized Constructor with Validation
# ========================================================================
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
                # Use zero as default for non-constant variables
                push!(result_values, zero(field_type))
            end
        end

        # Return the instance as a NamedTuple
        return NamedTuple{concrete_names}(Tuple(result_values))
    else
        # For non-NamedTuple types, error since we need to return instances
        error("T(;kwargs...) is only supported for OfNamedTuple types, not $(T)")
    end
end

# ========================================================================
# @of Macro and Related Processing Functions
# ========================================================================

"""
    @of(field1=spec1, field2=spec2, ...)

Create an OfNamedTuple type with cleaner syntax that allows direct references
between fields without needing symbols.

# Examples
```julia
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
    # For arithmetic expressions with field references
    if expr.head == :call && length(expr.args) >= 2
        op = expr.args[1]
        if op in [:+, :-, :*, :/]
            # Convert expression to tuple format for SymbolicExpr
            tuple_args = []
            has_field_ref = false

            # Add the operator
            push!(tuple_args, QuoteNode(op))

            # Process arguments
            for arg in expr.args[2:end]
                if arg isa Symbol && arg in available_fields
                    push!(tuple_args, QuoteNode(arg))
                    has_field_ref = true
                elseif arg isa Expr
                    processed = process_expression_refs(arg, available_fields)
                    if processed isa Expr &&
                        processed.head == :curly &&
                        processed.args[1] == :SymbolicExpr
                        # This is a SymbolicExpr{...} type, extract the tuple
                        push!(tuple_args, processed.args[2])
                        has_field_ref = true
                    else
                        push!(tuple_args, processed)
                    end
                else
                    push!(tuple_args, arg)
                end
            end

            if has_field_ref
                # Return as SymbolicExpr type
                tuple_expr = Expr(:tuple, tuple_args...)
                return :(SymbolicExpr{$tuple_expr})
            else
                # No field references, return the expression as-is
                return expr
            end
        else
            # Not an arithmetic operation we support
            return expr
        end
    else
        return expr
    end
end

# ========================================================================
# Random Value Generation
# ========================================================================
function Base.rand(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot generate random array with symbolic dimensions. Use rand(T; kwargs...) with dimension values.",
        )
    end
    return rand(T, dims...)
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
        "Cannot generate random values for constants. Use rand(of(T; const_name=value)) after providing the constant value.",
    )
end

# ========================================================================
# Zero Value Generation
# ========================================================================
function Base.zero(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot create zero array with symbolic dimensions. Use zero(T; kwargs...) with dimension values.",
        )
    end
    return zeros(T, dims...)
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
        "Cannot generate zero values for constants. Use zero(of(T; const_name=value)) after providing the constant value.",
    )
end

# ========================================================================
# Missing Value Generation
# ========================================================================
function Base.missing(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error(
            "Cannot create missing array with symbolic dimensions. Use missing(T; kwargs...) with dimension values.",
        )
    end
    return fill(missing, dims...)
end

function Base.missing(::Type{OfReal{L,U}}) where {L,U}
    return missing
end

function Base.missing(::Type{OfInt{L,U}}) where {L,U}
    return missing
end

function Base.missing(::Type{OfNamedTuple{Names,Types}}) where {Names,Types}
    values = Tuple(Base.missing(T) for T in Types.parameters)
    return NamedTuple{Names}(values)
end

function Base.missing(::Type{OfConstantWrapper{T}}) where {T}
    return error(
        "Cannot generate missing values for constants. Use missing(of(T; const_name=value)) after providing the constant value.",
    )
end

# Create instance with missing values from concretized of type
function Base.missing(T::Type{<:OfType})
    if T <: OfNamedTuple
        # Check if type has unresolved constants/symbols
        if has_symbolic_dims(T)
            missing_symbols = get_unresolved_symbols(T)
            error(
                "Cannot create missing instance for type with unresolved symbols: $(join(missing_symbols, ", ")). Use missing(of(T; kwargs...)) after providing constant values.",
            )
        end

        names = get_names(T)
        types = get_types(T)

        # Create instance with all fields set to missing
        values = Tuple(Base.missing(types.parameters[i]) for i in 1:length(names))
        return NamedTuple{names}(values)
    elseif T <: OfArray
        dims = get_dims(T)
        if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
            error(
                "Cannot create missing array with symbolic dimensions. Use missing(of(T; kwargs...)) with dimension values.",
            )
        end
        return fill(missing, dims...)
    elseif T <: OfReal || T <: OfInt
        return missing
    elseif T <: OfConstantWrapper
        error("Cannot create missing values for constants.")
    else
        error("missing(T) not implemented for type $(T)")
    end
end

# ========================================================================
# Size and Length Operations
# ========================================================================

# Get size of OfType types
function Base.size(::Type{OfArray{T,N,D}}) where {T,N,D}
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error("Cannot get size of array with symbolic dimensions.")
    end
    return dims
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
    dims = get_dims(OfArray{T,N,D})
    if any(d -> d isa Symbol || (d isa Type && d <: SymbolicExpr), dims)
        error("Cannot get length of array with symbolic dimensions.")
    end
    return prod(dims)
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

function _validate_leaf(::Type{OfReal{L,U}}, value) where {L,U}
    if value isa Real
        val = convert(Float64, value)
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

# Public flatten function
function flatten(::Type{T}, values) where {T<:OfType}
    return _flatten_impl(T, values)
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

# Public unflatten function
function unflatten(::Type{T}, flat_values::Vector{<:Real}) where {T<:OfType}
    return _unflatten_impl(T, flat_values)
end

# ========================================================================
# Display Helper Functions
# ========================================================================

# Format a bound type for display
function format_bound(bound_type, constant_fields, use_color)
    if bound_type === Nothing
        return "nothing"
    elseif bound_type <: Val
        return string(type_to_bound(bound_type))
    elseif bound_type <: SymbolicRef
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
            if L <: SymbolicRef && type_to_bound(L) in constant_fields
                printstyled(io, string(type_to_bound(L)); color=:cyan)
            else
                printstyled(io, lower_str; color=:cyan)
            end
            printstyled(io, ", "; color=:cyan)
            # Handle upper bound
            if U <: SymbolicRef && type_to_bound(U) in constant_fields
                printstyled(io, string(type_to_bound(U)); color=:cyan)
            else
                printstyled(io, upper_str; color=:cyan)
            end
            printstyled(io, "; constant=true"; color=:light_black)
            printstyled(io, ")"; color=:cyan)
        else
            print(io, "of($type_name, ")
            # Handle lower bound
            if L <: SymbolicRef && type_to_bound(L) in constant_fields && use_color
                printstyled(io, string(type_to_bound(L)); color=:cyan)
            else
                print(io, lower_str)
            end
            print(io, ", ")
            # Handle upper bound
            if U <: SymbolicRef && type_to_bound(U) in constant_fields && use_color
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

function Base.show(io::IO, ::Type{OfReal{L,U}}) where {L,U}
    return show_bounded_type(io, "Real", L, U)
end

function Base.show(io::IO, ::Type{OfInt{L,U}}) where {L,U}
    return show_bounded_type(io, "Int", L, U)
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

    # Check if we should use multi-line format
    compact = get(io, :compact, false)
    multiline = !compact && length(Names) > 3

    # For very long single-line output, also use multiline
    if !multiline && !compact
        # Estimate the output length
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
        multiline = total_length > 80
    end

    if multiline
        println(io, "@of(")
        indent = "    "
        for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
            print(io, indent)

            # Check if this field is a constant
            is_constant = T <: OfConstantWrapper

            if is_constant && get(io, :color, false)
                # Print constant fields in yellow
                printstyled(io, name; color=:cyan, bold=true)
            else
                print(io, name)
            end

            print(io, " = ")

            # For constants, show the wrapped type with styling
            if is_constant && get(io, :color, false)
                # Show the wrapped type content
                wrapped = get_wrapped_type(T)
                if wrapped <: OfReal &&
                    get_lower(wrapped) === Nothing &&
                    get_upper(wrapped) === Nothing
                    printstyled(io, "of(Real"; color=:cyan)
                    printstyled(io, "; constant=true"; color=:light_black)
                    printstyled(io, ")"; color=:cyan)
                elseif wrapped <: OfInt &&
                    get_lower(wrapped) === Nothing &&
                    get_upper(wrapped) === Nothing
                    printstyled(io, "of(Int"; color=:cyan)
                    printstyled(io, "; constant=true"; color=:light_black)
                    printstyled(io, ")"; color=:cyan)
                else
                    # For other constant types, use default show with constants context
                    show(io_with_constants, T)
                end
            else
                # Show non-constant fields with the constants context
                show(io_with_constants, T)
            end

            if i < length(Names)
                println(io, ",")
            else
                println(io)
            end
        end
        print(io, ")")
    else
        # Single line format (original behavior)
        print(io, "@of(")
        for (i, (name, T)) in enumerate(zip(Names, Types.parameters))
            # Check if this field is a constant
            is_constant = T <: OfConstantWrapper

            if is_constant && get(io, :color, false)
                # Print constant fields in yellow
                printstyled(io, name; color=:cyan, bold=true)
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
                    printstyled(io, "of(Real"; color=:cyan)
                    printstyled(io, "; constant=true"; color=:light_black)
                    printstyled(io, ")"; color=:cyan)
                elseif wrapped <: OfInt &&
                    get_lower(wrapped) === Nothing &&
                    get_upper(wrapped) === Nothing
                    printstyled(io, "of(Int"; color=:cyan)
                    printstyled(io, "; constant=true"; color=:light_black)
                    printstyled(io, ")"; color=:cyan)
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
        print(io, ")")
    end
end

function Base.show(io::IO, ::Type{OfConstantWrapper{T}}) where {T}
    # Show the wrapped type with constant=true
    if T <: OfReal
        show_bounded_type(io, "Real", get_lower(T), get_upper(T); constant=true)
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
