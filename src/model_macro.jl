using MacroTools

# The `@capture` macro from MacroTools is used to pattern-match Julia code.
# When a variable in the pattern is followed by a single underscore (e.g., `var_`), 
# it captures a single component of the Julia expression and binds it locally to that 
# variable name. If a variable is followed by double underscores (e.g., `vars__`), 
# it captures multiple components into an array.

macro model(model_function_expr)
    return _generate_model_definition(model_function_expr, __source__, __module__)
end

function _generate_model_definition(model_function_expr, __source__, __module__)
    MacroTools.@capture(
        #! format: off
        model_function_expr,
        function model_name_(param_destructure_, constant_variables__)
            body_expr__
        end
        #! format: on
    ) || return :(throw(ArgumentError("Expected a model function definition")))

    model_def = _add_line_number_nodes(Expr(:block, body_expr...)) # hack, see _add_line_number_nodes
    Parser.warn_cumulative_density_deviance(model_def) # refer to parser/bugs_macro.jl

    bugs_ast = Parser.bugs_top(model_def, __source__)

    # Parse different parameter destructuring patterns
    param_type = nothing
    param_fields = Symbol[]
    is_of_type = false

    # Try to match different parameter patterns
    if MacroTools.@capture(param_destructure, ((; fields__)::ptype_))
        # NamedTuple with type annotation: (;x, y, z)::ParamType
        param_type = ptype
        param_fields = extract_field_names(fields)
        # Check if it's an of type
        is_of_type = check_if_of_type(ptype)
    elseif MacroTools.@capture(param_destructure, (; fields__))
        # NamedTuple without type annotation: (;x, y, z)
        param_fields = extract_field_names(fields)
    else
        return :(throw(
            ArgumentError(
                "The first argument of the model function must be a destructuring assignment (e.g., (; x, y, z)).",
            ),
        ))
    end

    illegal_constant_variables = Any[]
    constant_variables_symbols = map(constant_variables) do constant_variable
        if constant_variable isa Symbol
            return constant_variable
        elseif MacroTools.@capture(
            constant_variable, ((name_ = default_value_) | (name_::type_))
        )
            return name_
        else
            push!(illegal_constant_variables, constant_variable)
        end
    end
    if !isempty(illegal_constant_variables)
        formatted_vars = join(illegal_constant_variables, ", ", " and ")
        return MacroTools.@q error(
            string(
                "The following arguments are not supported syntax for the model function currently: ",
                $(QuoteNode(formatted_vars)),
                "Please report this issue at https://github.com/TuringLang/JuliaBUGS.jl/issues",
            ),
        )
    end

    vars_and_numdims = extract_variable_names_and_numdims(bugs_ast)
    vars_assigned_to = extract_variables_assigned_to(bugs_ast)
    stochastic_vars = [vars_assigned_to[2]..., vars_assigned_to[4]...]
    deterministic_vars = [vars_assigned_to[1]..., vars_assigned_to[3]...]
    all_vars = collect(keys(vars_and_numdims))
    constants = setdiff(all_vars, vcat(stochastic_vars, deterministic_vars))

    # Check if all constants used in the model are included in function arguments
    if !all(in(constant_variables), constants)
        missing_constants = setdiff(constants, constant_variables)
        formatted_vars = join(missing_constants, ", ", " and ")
        return MacroTools.@q error(
            string(
                "The following constants used in the model are not included in the function arguments: ",
                $(QuoteNode(formatted_vars)),
            ),
        )
    end

    # Check if all stochastic variables are included in the parameters struct
    missing_stochastic_vars = setdiff(stochastic_vars, param_fields)
    if !isempty(missing_stochastic_vars)
        formatted_vars = join(missing_stochastic_vars, ", ", " and ")
        return MacroTools.@q error(
            string(
                "The following stochastic variables used in the model are not included in the parameters ",
                "in the first argument of the model function: ",
                $(QuoteNode(formatted_vars)),
            ),
        )
    end

    # Generate function based on parameter style
    if is_of_type
        # Type annotation with of type
        func_expr = MacroTools.@q function ($(esc(model_name)))(
            params_struct, $(esc.(constant_variables)...)
        )
            # For of types, we need to handle parameter extraction differently
            # params_struct is an instance of the of type
            # param_fields tells us which fields to extract as parameters

            extracted_params = _extract_params_from_of_type(
                params_struct, $(esc(param_type)), $(QuoteNode(param_fields))
            )

            # Merge with constants
            data = merge(
                extracted_params,
                NamedTuple{$(QuoteNode(Tuple(constant_variables)))}(
                    tuple($(esc.(constant_variables)...))
                ),
            )

            model_def = $(QuoteNode(bugs_ast))
            return compile(model_def, data)
        end
    else
        # Traditional style with type annotation or plain destructuring
        func_expr = MacroTools.@q function ($(esc(model_name)))(
            params_struct, $(esc.(constant_variables)...)
        )
            # Extract only the fields that are provided
            provided_params = NamedTuple()
            for field in $(QuoteNode(param_fields))
                if haskey(params_struct, field)
                    provided_params = merge(
                        provided_params, NamedTuple{(field,)}((params_struct[field],))
                    )
                end
            end

            # Merge with constants
            data = merge(
                provided_params,
                NamedTuple{$(QuoteNode(Tuple(constant_variables)))}(
                    tuple($(esc.(constant_variables)...))
                ),
            )

            model_def = $(QuoteNode(bugs_ast))
            return compile(model_def, data)
        end
    end

    return func_expr
end

function _param_struct_to_NT(param_struct)
    if param_struct isa NamedTuple
        # For NamedTuple, just filter out missing values
        pairs = Pair{Symbol,Any}[]
        for (k, v) in pairs(param_struct)
            if v !== missing
                push!(pairs, k => v)
            end
        end
        return NamedTuple(pairs)
    else
        # For structs, check field values
        field_names = fieldnames(typeof(param_struct))
        pairs = Pair{Symbol,Any}[]

        for field_name in field_names
            value = getfield(param_struct, field_name)
            if value !== missing
                push!(pairs, field_name => value)
            end
        end

        return NamedTuple(pairs)
    end
end

# This function addresses a discrepancy in how Julia's parser handles LineNumberNode insertion.
# When parsing a function body, the parser only adds a LineNumberNode before the first statement.
# In contrast, when parsing a "begin ... end" block, it inserts a LineNumberNode before each statement.
# The `bugs_top` function assumes input comes from a macro and expects a LineNumberNode before each statement.
# As a workaround, this function ensures that a LineNumberNode precedes every statement in the model function's body.
function _add_line_number_nodes(expr)
    if !(expr isa Expr)
        return expr
    end

    if Meta.isexpr(expr, :block)
        new_args = []

        for arg in expr.args
            if !(arg isa LineNumberNode) &&
                (isempty(new_args) || !(new_args[end] isa LineNumberNode))
                push!(new_args, LineNumberNode(0, :none)) # use a dummy LineNumberNode
            end

            push!(new_args, arg isa Expr ? _add_line_number_nodes(arg) : arg)
        end

        return Expr(:block, new_args...)
    else
        new_args = map(arg -> _add_line_number_nodes(arg), expr.args)
        return Expr(expr.head, new_args...)
    end
end

# Helper function to extract field names from various patterns
function extract_field_names(fields)
    field_names = Symbol[]
    for field in fields
        if field isa Symbol
            push!(field_names, field)
        elseif field isa Expr && field.head == :(::) && length(field.args) == 2
            name = field.args[1]
            type_expr = field.args[2]
            # Check if this is an inline of-type annotation
            if type_expr isa Expr &&
                type_expr.head == :call &&
                length(type_expr.args) >= 1 &&
                type_expr.args[1] == :of
                error(
                    "Inline of-type annotations are not supported. Use external type definitions with @of macro instead.",
                )
            end
            push!(field_names, name)
        else
            error("Unsupported field pattern: $field")
        end
    end
    return field_names
end

# Check if a type is an of type
function check_if_of_type(type_expr)
    # Check if the type expression references an of type
    # This is a heuristic - we check if it's a symbol that might be an of type
    # or if it's a type expression that includes OfNamedTuple
    return type_expr isa Symbol || (type_expr isa Expr && occursin("of", string(type_expr)))
end

# Extract parameters from an of type instance
function _extract_params_from_of_type(of_instance, of_type, param_names)
    # This function extracts the specified parameters from an of type instance
    # It handles both NamedTuple instances and of type instances

    if of_instance isa NamedTuple
        # Direct NamedTuple - extract specified fields
        # Only extract fields that exist in the instance
        available_names = keys(of_instance)
        params_to_extract = [name for name in param_names if name in available_names]

        if isempty(params_to_extract)
            # No parameters with values, return empty NamedTuple
            return NamedTuple()
        end

        extracted = NamedTuple{Tuple(params_to_extract)}(
            tuple((of_instance[name] for name in params_to_extract)...)
        )
        return extracted
    else
        # For of types created without values, return empty NamedTuple
        # The compile function will handle missing parameter values
        return NamedTuple()
    end
end
