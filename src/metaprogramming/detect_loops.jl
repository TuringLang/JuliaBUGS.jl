struct DetectLoops <: Analysis end

const __num_deterministic_vars_to_compute__ = gensym(:num_deterministic_vars_to_compute)
const __num_stochastic_vars_to_compute__ = gensym(:num_stochastic_vars_to_compute)

function generate_analysis_function(
    analysis::DetectLoops,
    simplified_model_def::Expr,
    ::NamedTuple{all_vars},
    num_deterministic_vars::Int,
    num_stochastic_vars::Int,
) where {all_vars}
    return @q function __detect_loops($__evaluate_env__::NamedTuple)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        $__num_deterministic_vars_to_compute__ = $num_deterministic_vars
        $__num_stochastic_vars_to_compute__ = $num_stochastic_vars

        $__added_new_val__ = true
        while $__added_new_val__
            $__added_new_val__ = false
            $(generate_analysis_function_mainbody(analysis, simplified_model_def)...)
        end

        if $__num_deterministic_vars_to_compute__ > 0 ||
            $__num_stochastic_vars_to_compute__ > 0
            error("Not all variables were computed, loop(s) exists.")
        end
    end
end

function generate_analysis_function_mainbody(
    analysis::DetectLoops, simplified_model_def::Expr
)
    args = Expr[]
    for statement in simplified_model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(args, @q(JuliaBUGS.@loop_detect_deterministic_compute $lhs = $rhs))
        elseif @capture(
            statement,
            if cond_
                body_
            end
        ) # `if` is introduced after `LoopIteration` to guard against already computed deterministic variables 
            @capture(only(body), lhs_ = rhs_)
            push!(args, @q(JuliaBUGS.@loop_detect_deterministic_compute $lhs = $rhs))
        elseif @capture(statement, lhs_ ~ rhs_)
            push!(args, @q(JuliaBUGS.@loop_detect_stochastic_compute $lhs ~ $rhs))
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(generate_analysis_function_mainbody(analysis, body)...)
                end
            ))
        else
            push!(args, statement)
        end
    end
    return args
end

function add_JuliaBUGS_prefix_to_functions(expr::Expr)
    return MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, f_(args__))
            if f isa Symbol && (
                f ∈ JuliaBUGS.BUGSPrimitives.BUGS_DISTRIBUTIONS ||
                f ∈ JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS
            )
                return @q(JuliaBUGS.BUGSPrimitives.$f($(args...)))
            end
        end
        return sub_expr
    end
end

macro _try_eval(expr::Expr)
    return esc(@q(
        try
            $expr
        catch
            missing
        end
    ))
end

macro loop_detect_deterministic_compute(expr::Expr)
    return esc(_loop_detect_deterministic_compute(expr))
end

_is_concrete(::Missing) = false
_is_concrete(val::Union{Int,Float64}) = true
_is_concrete(val::Array{<:Union{Int,Float64}}) = true
_is_concrete(val::Array{Missing}) = false
# because assign to the same location multiple times is not allowed, check one element is enough
_is_concrete(val::AbstractArray) = !ismissing(first(val))

function _loop_detect_deterministic_compute(expr::Expr)
    @capture(expr, lhs_ = rhs_)
    rhs = add_JuliaBUGS_prefix_to_functions(rhs)
    if lhs isa Symbol
        return @q if !JuliaBUGS._is_concrete($lhs)
            $__rhs_val__ = JuliaBUGS.@_try_eval($rhs)
            if $__rhs_val__ !== missing
                $lhs = $__rhs_val__
                $__num_deterministic_vars_to_compute__ -= 1
                $__added_new_val__ = true
            end
        end
    else
        @capture(lhs, v_[i__])
        return @q if !JuliaBUGS._is_concrete($lhs)
            $__rhs_val__ = JuliaBUGS.@_try_eval($rhs)
            if $__rhs_val__ !== missing
                $v = BangBang.setindex!!($v, $__rhs_val__, $(i...))
                $__num_deterministic_vars_to_compute__ -= length($__rhs_val__)
                $__added_new_val__ = true
            end
        end
    end
end

macro loop_detect_stochastic_compute(expr::Expr)
    return esc(_loop_detect_stochastic_compute(expr))
end

function _loop_detect_stochastic_compute(expr::Expr)
    @capture(expr, lhs_ ~ rhs_)
    rhs = add_JuliaBUGS_prefix_to_functions(rhs)
    if lhs isa Symbol
        return @q if !JuliaBUGS._is_concrete($lhs)
            $__rhs_val__ = JuliaBUGS.@_try_eval($rhs)
            if $__rhs_val__ !== missing
                $__rhs_val__ = rand($__rhs_val__)
                $lhs = $__rhs_val__
                $__num_stochastic_vars_to_compute__ -= 1
                $__added_new_val__ = true
            end
        end
    else
        @capture(lhs, v_[i__])
        return @q if !JuliaBUGS._is_concrete($lhs)
            $__rhs_val__ = JuliaBUGS.@_try_eval($rhs)
            if $__rhs_val__ !== missing
                $__rhs_val__ = rand($__rhs_val__)
                $v = BangBang.setindex!!($v, $__rhs_val__, $(i...))
                $__num_stochastic_vars_to_compute__ -= length($__rhs_val__)
                $__added_new_val__ = true
            end
        end
    end
end
