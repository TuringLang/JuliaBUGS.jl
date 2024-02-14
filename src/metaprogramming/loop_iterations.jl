function remove_scalar_transformed_variable_exprs(
    expr::Expr, eval_env::NamedTuple{all_names}
) where {all_names}
    args = Expr[]
    for statement in expr.args
        if @capture(statement, lhs_ = rhs_)
            if lhs in all_names
                continue
            end
        end
        push!(args, statement)
    end
    return Expr(:block, args...)
end

function remove_array_transformed_variables_exprs(
    expr::Expr, eval_env::NamedTuple{all_names,types}
) where {all_names,types}
    ret_expr = Expr(:block)
    args = ret_expr.args
    for statement in expr.args
        if @capture(statement, lhs_ = rhs_)
            if lhs isa Symbol
                push!(args, statement)
            else
                @capture(lhs, v_[i__])
                type = types.parameters[findfirst(x -> x === v, all_names)]
                if Missing <: eltype(type)
                    push!(args, statement)
                else
                    continue
                end
            end
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            new_body = remove_array_transformed_variables_exprs(body, eval_env)
            if !isempty(new_body.args)
                push!(args, @q(
                    for $loop_var in ($lower):($upper)
                        $(new_body.args...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return ret_expr
end

struct LoopIteration <: Analysis end

function get_deterministic_statement_loop_bounds!(
    model_def::Expr,
    loop_bound::Tuple{Vararg{Expr}}=(),
    loop_bound_map::Vector{Tuple{Vararg{Expr}}}=Vector{Tuple{Vararg{Expr}}}(),
)
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(loop_bound_map, loop_bound)
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            get_deterministic_statement_loop_bounds!(
                body, (loop_bound..., @q(($lower):($upper))), loop_bound_map
            )
        end
    end
    return loop_bound_map
end

const loop_iter_hot_map = gensym(:loop_iter_hot_map)

function generate_analysis_function(::LoopIteration, expr::Expr, eval_env::NamedTuple)
    deter_loop_bounds = get_deterministic_statement_loop_bounds!(expr)
    all_vars = extract_all_vars(expr)
    main_body = loop_iter_generate_analysis_function_mainbody!(expr, eval_env)
    if isempty(main_body)
        return @q(
            function __decide_deterministic_loop_iterations_hot_maps(
                $__evaluate_env__::NamedTuple
            )
                return nothing
            end
        )
    else
        return @q function __decide_deterministic_loop_iterations_hot_maps(
            $__evaluate_env__
        )
            $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
            $loop_iter_hot_map = [
                $(
                    [
                        @q(trues(length.([$(i...)])...)) for
                        i in deter_loop_bounds if i !== ()
                    ]...
                ),
            ]
            $(loop_iter_generate_analysis_function_mainbody!(expr, eval_env)...)
            return $loop_iter_hot_map
        end
    end
end

function loop_iter_generate_analysis_function_mainbody!(
    model_def::Expr,
    eval_env::NamedTuple{all_names,types},
    statement_counter::Ref{Int}=Ref(0),
    loop_vars::Tuple{Vararg{Symbol}}=(),
) where {all_names,types}
    args = Expr[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            if lhs isa Symbol
                continue
            else
                @capture(lhs, v_[i__])
                type = types.parameters[findfirst(x -> x === v, all_names)]
                if eltype(type) === Missing
                    continue
                else
                    lhs_val = gensym(:lhs_val)
                    push!(
                        args,
                        @q(
                            begin
                                $lhs_val = $lhs
                                if $lhs_val isa Union{Int,Float64}
                                    $loop_iter_hot_map[$(statement_counter[])][$(
                                        loop_vars...
                                    )] = false
                                elseif $lhs_val isa AbstractArray &&
                                    all(!ismissing, $lhs_val)
                                    $loop_iter_hot_map[$(statement_counter[])][$(
                                        loop_vars...
                                    )] .= false
                                end
                            end
                        )
                    )
                end
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            body_args = loop_iter_generate_analysis_function_mainbody!(
                body, eval_env, statement_counter, (loop_vars..., loop_var)
            )
            if isempty(body_args)
                continue
            end
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(body_args...)
                end
            ))
        else
            push!(args, statement) # Debugging: don't change other type of statements
        end
    end
    return args
end

function transform_expr_with_hot_map(
    simplified_model_def::Expr,
    hot_map::Vector{<:BitArray},
    loop_vars::Tuple{Vararg{Symbol}}=(),
    statement_counter::Ref{Int}=Ref(0),
)
    args = Expr[]
    for statement in simplified_model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            if lhs isa Symbol
                push!(args, statement)
            else
                @capture(lhs, v_[i__])
                push!(
                    args,
                    @q(
                        if ($(loop_vars...),) ∈
                            $(Tuple.(findall(hot_map[statement_counter[]])))
                            $lhs = $rhs
                        end
                    )
                )
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            push!(args, statement)
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            new_args = transform_expr_with_hot_map(
                body, hot_map, (loop_vars..., loop_var), statement_counter
            ).args
            if !isempty(new_args)
                push!(args, @q(
                    for $loop_var in ($lower):($upper)
                        $(new_args...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return Expr(:block, args...)
end
