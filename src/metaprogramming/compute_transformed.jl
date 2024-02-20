struct ComputeTransformed <: Analysis end

const __evaluate_env__ = gensym(:evaluate_env)
const __added_new_val__ = gensym(:added_new_val)

function generate_function_expr(analysis::ComputeTransformed, expr::Expr, __source__::LineNumberNode)
    variable_names = extract_variable_names(expr)

    return @q function __compute_transformed!($__evaluate_env__::NamedTuple)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, variable_names...)), __evaluate_env__))

        $__added_new_val__ = true
        while $__added_new_val__
            $__added_new_val__ = false
            $(generate_function_body(analysis, expr, __source__)...)
        end

        return NamedTuple{$(Tuple(variable_names))}($(Expr(:tuple, variable_names...)))
    end
end

function generate_function_body(
    analysis::ComputeTransformed, model_def::Expr, __source__::LineNumberNode
)
    args = Any[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(args, @qq(JuliaBUGS.@try_compute($lhs = $rhs)))
        elseif @capture(statement, lhs_ ~ rhs_)
            nothing
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(generate_function_body(analysis, body, __source__)...)
                end
            ))
        else
            push!(args, statement)
        end
    end
    return args
end

macro try_compute(expr::Expr)
    return esc(_try_compute(expr))
end

function _try_compute(expr::Expr)
    @assert Meta.isexpr(expr, :(=))
    lhs, rhs = expr.args

    lhs_val = gensym(:lhs_val)
    rhs_val = gensym(:rhs_val)
    ret_expr = @q begin
        $lhs_val = $lhs
        if $lhs_val isa Union{Int,Float64} ||
            ($lhs_val isa AbstractArray && all(!ismissing, $lhs_val))
        else
            $(
                (
                    if rhs isa Union{Int,Float64}
                        @q begin
                            $lhs = $rhs
                            $__added_new_val__ = true
                        end
                    elseif rhs isa Symbol
                        @q begin
                            if !ismissing($rhs)
                                $lhs = $rhs
                                $__added_new_val__ = true
                            end
                        end
                    else
                        rhs = MacroTools.postwalk(rhs) do sub_expr
                            if @capture(sub_expr, f_(args__))
                                if f isa Symbol && f ∈ JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS
                                    return @q(JuliaBUGS.BUGSPrimitives.$f($(args...)))
                                end
                            end
                            return sub_expr
                        end
                        @q begin
                            $rhs_val = try
                                $rhs
                            catch
                            end
                            if $rhs_val isa Union{Int,Float64}
                                $lhs = $rhs_val
                                $__added_new_val__ = true
                            elseif !ismissing($rhs_val) && all(!ismissing, $rhs_val)
                                $lhs .= $rhs_val
                                $__added_new_val__ = true
                            end
                        end
                    end
                ).args...
            )
        end
    end

    return ret_expr
end
