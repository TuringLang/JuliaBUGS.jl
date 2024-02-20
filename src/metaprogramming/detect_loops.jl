struct CountFreeVars <: Analysis end

const __num_free_deterministic_vars__ = gensym(:num_free_deterministic_vars)
const __num_free_stochastic_vars__ = gensym(:num_free_stochastic_vars)

function generate_function_expr(analysis::CountFreeVars, expr::Expr)
    all_vars = extract_variable_names(expr)

    return @q function __count_free_vars($__evaluate_env__::NamedTuple)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        $__num_free_deterministic_vars__, $__num_free_stochastic_vars__ = 0, 0
        $(generate_function_body(analysis, expr)...)
        return ($__num_free_deterministic_vars__, $__num_free_stochastic_vars__)
    end
end

function generate_function_body(analysis::CountFreeVars, model_def::Expr)
    args = Any[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(
                args,
                if lhs isa Symbol
                    @q if ismissing($lhs)
                        $__num_free_deterministic_vars__ += 1
                    end

                else
                    @q if !JuliaBUGS._is_concrete($lhs)
                        $__num_free_deterministic_vars__ += prod(
                            map(length, [$(lhs.args[2:end]...)])
                        )
                    end
                end,
            )
        elseif @capture(statement, lhs_ ~ rhs_)
            push!(
                args,
                if lhs isa Symbol
                    @q if ismissing($lhs)
                        $__num_free_stochastic_vars__ += 1
                    end

                else
                    @q if !JuliaBUGS._is_concrete($lhs)
                        $__num_free_stochastic_vars__ += prod(
                            map(length, [$(lhs.args[2:end]...)])
                        )
                    end
                end,
            )
        elseif @capture(
            statement,
            for loop_var_ in loop_bounds_
                body_
            end
        )
            push!(args, @q for $loop_var in $loop_bounds
                $(generate_function_body(analysis, body)...)
            end)
        else
            push!(args, statement) # Debugging: don't change other type of statements
        end
    end
    return args
end

struct DetectLoops <: Analysis end

const __num_deterministic_vars_to_compute__ = gensym(:num_deterministic_vars_to_compute)
const __num_stochastic_vars_to_compute__ = gensym(:num_stochastic_vars_to_compute)
# some Bijectors.bijector can have different dimensionality, so we need to keep track of the number of transformed variables
# this assumes that the dimension of transformed variables are consistent
const __num_transformed_stochastic_vars_to_compute__ = gensym(
    :num_transformed_stochastic_vars_to_compute
)
# effectively how many nodes are there in the graph
const __num_statement_instances__ = gensym(:num_statement_instances)

function generate_function_expr(
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
        $__num_transformed_stochastic_vars_to_compute__ = 0

        $__added_new_val__ = true
        while $__added_new_val__
            $__added_new_val__ = false
            $(generate_function_body(analysis, simplified_model_def)...)
        end

        if $__num_deterministic_vars_to_compute__ > 0 ||
            $__num_stochastic_vars_to_compute__ > 0
            error("Not all variables were computed, loop(s) exists.")
        end

        return $__num_transformed_stochastic_vars_to_compute__
    end
end

function generate_function_body(analysis::DetectLoops, simplified_model_def::Expr)
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
                    $(generate_function_body(analysis, body)...)
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

# TODO: will write to arrays with missing values
function _loop_detect_stochastic_compute(expr::Expr)
    @capture(expr, lhs_ ~ rhs_)
    rhs = add_JuliaBUGS_prefix_to_functions(rhs)
    if lhs isa Symbol
        return @q if !JuliaBUGS._is_concrete($lhs)
            $__rhs_val__ = JuliaBUGS.@_try_eval($rhs)
            if $__rhs_val__ !== missing
                $__num_transformed_stochastic_vars_to_compute__ += length(
                    Bijectors.transformed($__rhs_val__)
                )
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
                $__num_transformed_stochastic_vars_to_compute__ += length(
                    Bijectors.transformed($__rhs_val__)
                )
                $__rhs_val__ = rand($__rhs_val__)
                $v = BangBang.setindex!!($v, $__rhs_val__, $(i...))
                $__num_stochastic_vars_to_compute__ -= length($__rhs_val__)
                $__added_new_val__ = true
            end
        end
    end
end

function remove_scalar_transformed_variable_exprs(
    expr::Expr, ::NamedTuple{all_names}
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

function remove_array_transformed_variables_exprs(expr::Expr, eval_env::NamedTuple)
    return Expr(:block, remove_array_transformed_variables_exprs_block(expr, eval_env)...)
end

function remove_array_transformed_variables_exprs_block(
    expr::Expr, eval_env::NamedTuple{all_names,types}
) where {all_names,types}
    args = Expr[]
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
            _args = remove_array_transformed_variables_exprs_block(body, eval_env)
            if !isempty(_args)
                push!(args, @q(
                    for $loop_var in ($lower):($upper)
                        $(_args...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return args
end
