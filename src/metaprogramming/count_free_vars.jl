struct CountFreeVars <: Analysis end

const __num_free_deterministic_vars__ = gensym(:num_free_deterministic_vars)
const __num_free_stochastic_vars__ = gensym(:num_free_stochastic_vars)

function generate_analysis_function(analysis::CountFreeVars, expr::Expr)
    all_vars = Tuple(keys(extract_array_ndims(expr)))

    return @q function __count_free_vars(
        $__evaluate_env__::NamedTuple{$__ALL_VARS__}
    ) where {$__ALL_VARS__}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        $__num_free_deterministic_vars__ = 0
        $__num_free_stochastic_vars__ = 0
        $(generate_analysis_function_mainbody!(analysis, expr)...)
        return ($__num_free_deterministic_vars__, $__num_free_stochastic_vars__)
    end
end

const __lhs_val__ = gensym(:lhs_val)

function generate_analysis_function_statement_deterministic(
    ::CountFreeVars, lhs::Symbol, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
    @q(
        if ismissing($lhs)
            $__num_free_deterministic_vars__ += 1
        end
    )
end

function generate_analysis_function_statement_deterministic(
    ::CountFreeVars, lhs::Expr, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
    @q begin
        $__lhs_val__ = $lhs
        if !(
            $__lhs_val__ isa Union{Int,Float64} ||
            ($__lhs_val__ isa AbstractArray && all(!ismissing, $__lhs_val__))
        )
            $__num_free_deterministic_vars__ += prod(map(length, [$(lhs.args[2:end]...)]))
        end
    end
end

function generate_analysis_function_statement_stochastic(
    ::CountFreeVars, lhs::Symbol, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
    @q(
        if ismissing($lhs)
            $__num_free_stochastic_vars__ += 1
        end
    )
end

function generate_analysis_function_statement_stochastic(
    ::CountFreeVars, lhs::Expr, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
    @q begin
        $__lhs_val__ = $lhs
        if !(
            $__lhs_val__ isa Union{Int,Float64} ||
            ($__lhs_val__ isa AbstractArray && all(!ismissing, $__lhs_val__))
        )
            $__num_free_stochastic_vars__ += prod(map(length, [$(lhs.args[2:end]...)]))
        end
    end
end
