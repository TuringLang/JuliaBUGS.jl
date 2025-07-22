using MacroTools

macro model(model_function_expr)
    return _generate_model_definition(model_function_expr, __source__, __module__)
end

function _generate_model_definition(model_function_expr, __source__, __module__)
    parsed = _parse_model_function(model_function_expr)
    parsed === nothing &&
        return :(throw(ArgumentError("Expected a model function definition")))

    model_name, param_destructure, constant_variables, body_expr = parsed

    model_def = _add_line_number_nodes(Expr(:block, body_expr...))
    Parser.warn_cumulative_density_deviance(model_def)
    bugs_ast = Parser.bugs_top(model_def, __source__)

    param_parse_result = _parse_parameter_destructuring(param_destructure)
    param_parse_result === nothing && return :(throw(
        ArgumentError(
            "The first argument of the model function must be a destructuring assignment (e.g., (; x, y, z)).",
        ),
    ))
    param_type, param_fields = param_parse_result

    constant_processing_result = _process_constant_variables(constant_variables)
    if constant_processing_result isa Expr
        return constant_processing_result
    end
    constant_names = constant_processing_result

    validation_error = _validate_model_consistency(bugs_ast, param_fields, constant_names)
    if validation_error !== nothing
        return validation_error
    end

    return _generate_model_function(
        model_name, param_type, param_fields, constant_variables, constant_names, bugs_ast
    )
end

function _generate_model_function(
    model_name, param_type, param_fields, constant_variables, constant_names, bugs_ast
)
    return MacroTools.@q function ($(esc(model_name)))(
        params_struct, $(esc.(constant_variables)...)
    )
        extracted_params = _extract_model_params(params_struct, $(QuoteNode(param_fields)))

        data = merge(
            extracted_params,
            NamedTuple{$(QuoteNode(Tuple(constant_names)))}(
                tuple($(esc.(constant_names)...))
            ),
        )

        model = compile($(QuoteNode(bugs_ast)), data)

        if $(param_type !== nothing)
            try
                _validate($(esc(param_type)), model.evaluation_env)
            catch e
                if e isa MethodError
                    error(
                        "Type annotation `$($(esc(param_type)))` is not supported. " *
                        "Only of types created with @of macro are supported for type annotations. " *
                        "Either remove the type annotation or use an of type.",
                    )
                elseif e isa ErrorException
                    error(
                        "Model evaluation_env does not match the expected type specification: $(e.msg)",
                    )
                else
                    rethrow(e)
                end
            end
        end

        return model
    end
end

# Workaround for Julia parser discrepancy: ensures LineNumberNode precedes each statement
# as expected by bugs_top (which assumes macro with "begin...end" block syntax)
function _add_line_number_nodes(expr)
    if !(expr isa Expr)
        return expr
    end

    if Meta.isexpr(expr, :block)
        new_args = []

        for arg in expr.args
            if !(arg isa LineNumberNode) &&
                (isempty(new_args) || !(new_args[end] isa LineNumberNode))
                push!(new_args, LineNumberNode(0, :none))
            end

            push!(new_args, arg isa Expr ? _add_line_number_nodes(arg) : arg)
        end

        return Expr(:block, new_args...)
    else
        new_args = map(arg -> _add_line_number_nodes(arg), expr.args)
        return Expr(expr.head, new_args...)
    end
end

function _parse_model_function(model_function_expr)
    MacroTools.@capture(
        #! format: off
        model_function_expr,
        function model_name_(param_destructure_, constant_variables__)
            body_expr__
        end
        #! format: on
    ) || return nothing

    return (model_name, param_destructure, constant_variables, body_expr)
end

function _parse_parameter_destructuring(param_destructure)
    if MacroTools.@capture(param_destructure, ((; fields__)::ptype_))
        return (ptype, validate_and_extract_field_names(fields))
    elseif MacroTools.@capture(param_destructure, (; fields__))
        return (nothing, validate_and_extract_field_names(fields))
    else
        return nothing
    end
end

function _process_constant_variables(constant_variables)
    illegal_constant_variables = Any[]
    constant_variables_symbols = map(constant_variables) do constant_variable
        if constant_variable isa Symbol
            return constant_variable
        elseif MacroTools.@capture(constant_variable, name_ = default_value_)
            return name
        elseif MacroTools.@capture(constant_variable, name_::type_)
            return name
        else
            push!(illegal_constant_variables, constant_variable)
            return nothing
        end
    end

    if !isempty(illegal_constant_variables)
        formatted_vars = join(illegal_constant_variables, ", ", " and ")
        return MacroTools.@q error(
            string(
                "Unsupported argument syntax: ",
                $(QuoteNode(formatted_vars)),
                ". Expected: name, name=default, or name::Type",
            ),
        )
    end

    return filter(!isnothing, constant_variables_symbols)
end

function _validate_model_consistency(bugs_ast, param_fields, constant_names)
    variable_info = extract_variable_names_and_numdims(bugs_ast)
    variable_assignments = extract_variables_assigned_to(bugs_ast)

    stochastic_vars = vcat(variable_assignments[2]..., variable_assignments[4]...)
    deterministic_vars = vcat(variable_assignments[1]..., variable_assignments[3]...)
    all_vars = collect(keys(variable_info))
    constants = setdiff(all_vars, vcat(stochastic_vars, deterministic_vars))

    missing_constants = setdiff(constants, constant_names)
    if !isempty(missing_constants)
        formatted_vars = join(missing_constants, ", ", " and ")
        return MacroTools.@q error(
            string(
                "Missing constants in function arguments: ", $(QuoteNode(formatted_vars))
            ),
        )
    end

    missing_stochastic_vars = setdiff(stochastic_vars, param_fields)
    if !isempty(missing_stochastic_vars)
        formatted_vars = join(missing_stochastic_vars, ", ", " and ")
        return MacroTools.@q error(
            string(
                "Missing stochastic variables in parameters: ", $(QuoteNode(formatted_vars))
            ),
        )
    end

    return nothing
end

function validate_and_extract_field_names(fields)
    for field in fields
        if !(field isa Symbol)
            if field isa Expr && field.head == :(::)
                error(
                    "Inline type annotations are not supported in @model macro. " *
                    "Found `$field`. Use plain destructuring `(; x, y, z)` without type annotations, " *
                    "or apply a type annotation to the entire pattern: `(; x, y, z)::MyType`",
                )
            else
                error(
                    "Invalid field pattern in @model macro: `$field`. " *
                    "Only plain symbols are allowed in destructuring patterns.",
                )
            end
        end
    end
    return Symbol[fields...]
end

function _extract_model_params(params_struct, param_fields)
    if params_struct isa NamedTuple
        available_names = keys(params_struct)
        params_to_extract = [name for name in param_fields if name in available_names]

        isempty(params_to_extract) && return NamedTuple()

        return NamedTuple{Tuple(params_to_extract)}(
            tuple((params_struct[name] for name in params_to_extract)...)
        )
    else
        provided_params = NamedTuple()
        for field in param_fields
            if hasproperty(params_struct, field)
                value = getproperty(params_struct, field)
                if value !== missing
                    provided_params = merge(provided_params, NamedTuple{(field,)}((value,)))
                end
            end
        end
        return provided_params
    end
end
