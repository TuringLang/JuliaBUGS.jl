using MacroTools

# The `@capture` macro from MacroTools is used to pattern-match Julia code.
# When a variable in the pattern is followed by a single underscore (e.g., `var_`), 
# it captures a single component of the Julia expression and binds it locally to that 
# variable name. If a variable is followed by double underscores (e.g., `vars__`), 
# it captures multiple components into an array.

struct ParameterPlaceholder end

macro parameters(struct_expr)
    if MacroTools.@capture(struct_expr, struct struct_name_
        struct_fields__
    end)
        return _generate_struct_definition(struct_name, struct_fields)
    else
        return :(throw(
            ArgumentError(
                "Expected a struct definition like '@parameters struct MyParams ... end'"
            ),
        ))
    end
end

function _generate_struct_definition(struct_name, struct_fields)
    if !isa(struct_name, Symbol)
        return :(throw(
            ArgumentError(
                "Parametrized types (e.g., `struct MyParams{T}`) are not supported yet"
            ),
        ))
    end

    if !all(isa.(struct_fields, Symbol))
        return :(throw(
            ArgumentError(
                "Field types are determined by JuliaBUGS automatically. Specify types for fields is not allowed for now.",
            ),
        ))
    end

    show_method_expr = MacroTools.@q function Base.show(
        io::IO, mime::MIME"text/plain", params::$(esc(struct_name))
    )
        # Use IOContext for potentially compact/limited printing of field values
        ioc = IOContext(io, :compact => true, :limit => true)

        println(ioc, "$(nameof(typeof(params))):")
        fields = fieldnames(typeof(params))

        # Handle empty structs gracefully
        if isempty(fields)
            print(ioc, "  (no fields)")
            return nothing
        end

        # Calculate maximum field name length for alignment
        max_len = maximum(length ∘ string, fields)
        for field in fields
            value = getfield(params, field)
            field_str = rpad(string(field), max_len)
            print(ioc, "  ", field_str, " = ")
            if value isa JuliaBUGS.ParameterPlaceholder
                # Use the IOContext here as well
                printstyled(ioc, "<placeholder>"; color=:light_black)
            else
                # Capture the string representation using the context
                # Use the basic `show` for a more compact representation, especially for arrays
                str_representation = sprint(show, value; context=ioc)
                # Print the captured string with color
                printstyled(ioc, str_representation; color=:cyan)
            end
            # Use the IOContext for the newline too
            println(ioc)
        end
    end

    return MacroTools.@q begin
        Base.@kwdef struct $(esc(struct_name))
            $(map(f -> :($(esc(f)) = ParameterPlaceholder()), struct_fields)...)
        end

        $(show_method_expr)

        function $(esc(struct_name))(model::BUGSModel)
            return getparams($(esc(struct_name)), model)
        end
    end
end

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

    param_type = nothing
    MacroTools.@capture(
        param_destructure, (((; param_fields__)::param_type_) | ((; param_fields__)))
    ) || return :(throw(
        ArgumentError(
            "The first argument of the model function must be a destructuring assignment with a type annotation defined using `@parameters`.",
        ),
    ))

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

    func_expr = MacroTools.@q function ($(esc(model_name)))(
        params_struct, $(esc.(constant_variables)...)
    )
        (; $(esc.(param_fields)...)) = params_struct
        data = _param_struct_to_NT((;
            $([esc.(param_fields)..., esc.(constant_variables)...]...)
        ))
        model_def = $(QuoteNode(bugs_ast))
        return compile(model_def, data)
    end

    if param_type === nothing
        return func_expr
    else
        return MacroTools.@q begin
            function JuliaBUGS.getparams($(esc(param_type)), model::BUGSModel)
                env = model.evaluation_env
                field_names = fieldnames($(esc(param_type)))
                kwargs = Dict{Symbol,Any}()

                for field in field_names
                    if haskey(env, field)
                        kwargs[field] = env[field]
                    end
                end

                return $(esc(param_type))(; kwargs...)
            end
            $func_expr
        end
    end
end

function _param_struct_to_NT(param_struct)
    field_names = fieldnames(typeof(param_struct))
    pairs = Pair{Symbol,Any}[]

    for field_name in field_names
        value = getfield(param_struct, field_name)
        if !(value isa ParameterPlaceholder)
            push!(pairs, field_name => value)
        end
    end

    return NamedTuple(pairs)
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
