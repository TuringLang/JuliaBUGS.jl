struct LoopIteration <: Analysis end

const __loop_iter_bitmaps__ = gensym(:loop_iter_bitmap)

function generate_function_expr(
    analysis::LoopIteration, expr::Expr, eval_env::NamedTuple{variables,type}
) where {variables,type}
    return @q function __compute_loop_iterations_bitmaps($__evaluate_env__)
        $(Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, extract_variable_names(expr)...)),
            __evaluate_env__,
        ))
        $__loop_iter_bitmaps__ = [
            $(initialize_loop_iter_bitmap!(extract_statement_loop_bounds(expr))...)
        ]
        $(
            generate_function_body(
                analysis, expr, NamedTuple{variables}(Tuple(type.parameters)), Ref(0), ()
            )...
        )
        return $__loop_iter_bitmaps__
    end
end

@inline function initialize_loop_iter_bitmap!(stmt_loop_bounds::Vector{Tuple{Vararg{Expr}}})
    args = Array{Expr}(undef, length(stmt_loop_bounds))
    for (i, loop_bounds) in enumerate(stmt_loop_bounds)
        args[i] = @q(trues(length.(($(loop_bounds...),))...))
    end
    return args
end

function generate_function_body(
    analysis::LoopIteration,
    model_def::Expr,
    eval_env_variables_types::NamedTuple{variables},
    statement_counter::Ref{Int},
    loop_vars::Tuple{Vararg{Symbol}},
) where {variables}
    args = Any[]
    for statement in model_def.args
        if @capture(statement, (lhs_ = rhs_) | (lhs_ ~ rhs_))
            statement_counter[] += 1
            if lhs isa Symbol
                push!(
                    args,
                    @q(
                        begin
                            if $lhs isa Union{Int,Float64}
                                $__loop_iter_bitmaps__[$(statement_counter[])][1] = false
                            end
                        end
                    )
                )
            else
                @capture(lhs, v_[i__])
                type = eval_env_variables_types[v]
                if eltype(type) === Missing
                    push!(args, :nothing)
                else
                    lhs_val = gensym(:lhs_val)
                    push!(
                        args,
                        @q(
                            begin
                                $lhs_val = $lhs
                                if $lhs_val isa Union{Int,Float64}
                                    $__loop_iter_bitmaps__[$(statement_counter[])][$(
                                        loop_vars...
                                    )] = false
                                elseif $lhs_val isa AbstractArray &&
                                    all(!ismissing, $lhs_val)
                                    $__loop_iter_bitmaps__[$(statement_counter[])][$(
                                        loop_vars...
                                    )] .= false
                                end
                            end
                        )
                    )
                end
            end
        elseif @capture(
            statement,
            for loop_var_ in loop_bounds_
                body_
            end
        )
            push!(
                args,
                @q(
                    for $loop_var in $loop_bounds
                        $(
                            generate_function_body(
                                analysis,
                                body,
                                eval_env_variables_types,
                                statement_counter,
                                (loop_vars..., loop_var),
                            )...
                        )
                    end
                )
            )
        else
            push!(args, statement)
        end
    end
    return args
end
