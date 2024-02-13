struct RefineLoopIterations <: Analysis end

function generate_analysis_function(analysis::RefineLoopIterations, expr::Expr)
    all_vars = Tuple(keys(extract_array_ndims(expr)))

    return @q function __count_free_vars(
        $__evaluate_env__::NamedTuple{$__ALL_VARS__}
    ) where {$__ALL_VARS__}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        $(generate_analysis_function_mainbody!(analysis, expr)...)
        return nothing
    end
end

function generate_analysis_function_statement_deterministic(
    ::RefineLoopIterations, lhs::Symbol, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
   
end

function generate_analysis_function_statement_deterministic(
    ::CountFreeVars, lhs::Expr, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)

end

function generate_analysis_function_statement_stochastic(
    ::CountFreeVars, lhs::Union{Symbol, Expr}, rhs::__RHS_UNION_TYPE__, statement_counter::Int
)
    return nothing
end
