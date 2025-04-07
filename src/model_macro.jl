using MacroTools

const __struct_name_to_field_name = Dict{Symbol,Vector{Symbol}}()

struct ParameterPlaceholder end

macro parameters(struct_expr)
    if MacroTools.@capture(struct_expr, struct struct_name_
        struct_fields__
    end)
        return _generate_struct_definition(struct_name, struct_fields)
    else
        # Use ArgumentError for invalid macro input
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
    elseif !all(isa.(struct_fields, Symbol))
        return :(throw(
            ArgumentError(
                "Field types are determined by JuliaBUGS automatically. Do not specify types in the struct definition.",
            ),
        ))
    end

    struct_name_quoted = QuoteNode(struct_name)
    struct_fields_quoted = [QuoteNode(f) for f in struct_fields]

    show_method_expr = quote
        function Base.show(io::IO, mime::MIME"text/plain", params::$(esc(struct_name)))
            println(io, "$(nameof(typeof(params))):")
            fields = fieldnames(typeof(params))
            max_len = isempty(fields) ? 0 : maximum(length ∘ string, fields)
            for field in fields
                value = getfield(params, field)
                field_str = rpad(string(field), max_len)
                print(io, "  ", field_str, " = ")
                if value isa JuliaBUGS.ParameterPlaceholder
                    printstyled(io, "<placeholder>"; color=:light_black)
                else
                    show(io, mime, value)
                end
                println(io)
            end
        end
    end

    return quote
        __struct_name_to_field_name[$(esc(struct_name_quoted))] = [
            $(esc.(struct_fields_quoted)...)
        ]

        Base.@kwdef struct $(esc(struct_name))
            $(map(f -> :($(esc(f)) = ParameterPlaceholder()), struct_fields)...)
        end

        $(show_method_expr)
    end
end

macro model(model_function_expr)
    return _generate_model_definition(model_function_expr, __source__)
end

function _generate_model_definition(model_function_expr, __source__)
    if MacroTools.@capture(
        #! format: off
        model_function_expr,
        function model_name_(param_splat_, constant_variables__)
            body_expr__
        end
        #! format: on
    )
        block_body_expr = Expr(:block, body_expr...)
        body_with_lines = _add_line_number_nodes(block_body_expr) # hack, see _add_line_number_nodes

        bugs_ast_input = body_with_lines

        # refer parser/bugs_macro.jl
        Parser.warn_cumulative_density_deviance(bugs_ast_input)
        bugs_ast = Parser.bugs_top(bugs_ast_input, __source__)

        vars_and_numdims = extract_variable_names_and_numdims(bugs_ast)
        vars_assigned_to = extract_variables_assigned_to(bugs_ast)
        stochastic_vars = [vars_assigned_to[2]..., vars_assigned_to[4]...]
        deterministic_vars = [vars_assigned_to[1]..., vars_assigned_to[3]...]
        all_vars = collect(keys(vars_and_numdims))
        constants = setdiff(all_vars, vcat(stochastic_vars, deterministic_vars))

        if MacroTools.@capture(param_splat, (; param_fields__)::param_type_)
            if !haskey(__struct_name_to_field_name, param_type)
                return :(error(
                    "$param_type is not registered as a parameter struct. Use `@parameters` to define it.",
                ))
            else
                # check if the field names coincide with stochastic_vars
                if !all(in(stochastic_vars), __struct_name_to_field_name[param_type])
                    return :(error(
                        "The field names of the struct definition of the parameters in the model function should coincide with the stochastic variables.",
                    ))
                end
            end

            if !all(in(constant_variables), constants)
                missing_constants = setdiff(constants, constant_variables)
                return :(error(
                    "The following constants used in the model are not included in the function arguments: $($(QuoteNode(missing_constants)))",
                ))
            end

            return esc(
                MacroTools.@q begin
                    __model_def__ = $(QuoteNode(bugs_ast))
                    function $model_name(
                        __params__::$(param_type), $(constant_variables...)
                    )
                        pairs_vector = Pair{Symbol,Any}[]
                        $(
                            map(
                                field_name -> quote
                                    val = __params__.$(field_name)
                                    if !(val isa JuliaBUGS.ParameterPlaceholder)
                                        push!(pairs_vector, $(QuoteNode(field_name)) => val)
                                    end
                                end,
                                __struct_name_to_field_name[param_type],
                            )...
                        )
                        data = NamedTuple(pairs_vector)
                        constants_nt = (; $(constant_variables...))
                        combined_data = Base.merge(data, constants_nt)

                        return compile(__model_def__, combined_data)
                    end
                end
            )
        else
            return :(throw(
                ArgumentError(
                    "The first argument of the model function must be a destructuring assignment with a type annotation defined using `@parameters`.",
                ),
            ))
        end
    else
        return :(throw(ArgumentError("Expected a model function definition")))
    end
end

# this is a hack, the reason I need this is that even the code is the same, if parsed as a function body
# the parser only inserts a LineNumberNode for the first statement, not for each statement in the body
# in contrast, if parsed as a "begin ... end" block, the parser inserts a LineNumberNode for each statement
# `bugs_top` made an assumption that the input is from a macro, so it assumes there is a LineNumberNode preceding each statement
# this function is a hack to ensure that there is a LineNumberNode preceding each statement in the body of the model function
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
