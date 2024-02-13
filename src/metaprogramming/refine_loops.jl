struct RefineLoopIterations <: Analysis end

function generate_analysis_function(analysis::RefineLoopIterations, expr::Expr)
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
