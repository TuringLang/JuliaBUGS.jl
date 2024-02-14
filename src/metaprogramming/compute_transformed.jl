function create_evaluate_env(
    all_vars::Tuple{Vararg{Symbol}},
    data::NamedTuple{data_vars,data_var_types},
    array_sizes::NamedTuple{array_vars},
) where {data_vars,data_var_types,array_vars}
    scalars_not_data = Tuple(setdiff(all_vars, array_vars, data_vars))
    array_vars_not_data = Tuple(setdiff(array_vars, data_vars))

    need_copy = [t <: Array && Missing <: eltype(t) for t in data_var_types.parameters]
    data_copy = NamedTuple{data_vars}(
        Tuple([
            if need_copy[i]
                copy(getfield(data, data_vars[i]))
            else
                getfield(data, data_vars[i])
            end for i in eachindex(data_vars)
        ])
    )

    init_scalars = Tuple([missing for i in 1:length(scalars_not_data)])
    init_arrays = Tuple([
        Array{__REAL_WITH_MISSING__}(missing, array_sizes[array_vars_not_data[i]]...) for
        i in eachindex(array_vars_not_data)
    ])

    return merge(
        data_copy,
        NamedTuple{scalars_not_data}(init_scalars),
        NamedTuple{array_vars_not_data}(init_arrays),
    )
end

struct ComputeTransformed <: Analysis end

const __added_new_val__ = gensym(:added_new_val)

function generate_analysis_function(analysis::ComputeTransformed, expr::Expr)
    all_vars = extract_all_vars(expr)

    return @q function __compute_transformed!(
        $__evaluate_env__::NamedTuple{$__ALL_VARS__}
    ) where {$__ALL_VARS__}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))

        $__added_new_val__ = true
        while $__added_new_val__
            $__added_new_val__ = false
            $(generate_analysis_function_mainbody(analysis, expr)...)
        end

        return NamedTuple{$(Tuple(all_vars))}($(Expr(:tuple, all_vars...)))
    end
end

function generate_analysis_function_statement_deterministic(
    ::ComputeTransformed, lhs::Union{Symbol,Expr}, rhs::__RHS_UNION_TYPE__
)
    return @q(JuliaBUGS.@try_compute($lhs = $rhs))
end

function generate_analysis_function_statement_stochastic(
    ::ComputeTransformed, lhs::Union{Symbol,Expr}, rhs::__RHS_UNION_TYPE__
)
    return nothing
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

function check_conflicts(
    eval_env::NamedTuple{variable_names},
    conflicted_scalars::Tuple{Vararg{Symbol}},
    conflicted_arrays::NamedTuple{array_names,array_types},
) where {variable_names,array_names,array_types}
    for scalar in conflicted_scalars
        if eval_env[scalar] isa Missing
            error("$scalar is assigned by both logical and stochastic variables.")
        end
    end

    for (array_name, conflict_array) in pairs(conflicted_arrays)
        missing_values = ismissing.(eval_env[array_name])
        conflicts = conflict_array .& missing_values
        if any(conflicts)
            error(
                "$(array_name)[$(join(Tuple.(findall(conflicts)), ", "))] is assigned by both logical and stochastic variables.",
            )
        end
    end
end

function concretize_eval_env_value_types(
    eval_env::NamedTuple{variable_names,variable_types}
) where {variable_names,variable_types}
    return NamedTuple{variable_names}(
        Tuple([
            if type === Missing ||
                type <: Union{Int,Float64} ||
                eltype(type) === Missing ||
                eltype(type) <: Union{Int,Float64}
                value
            else # Missing <: eltype(type)
                map(identity, value)
            end for (value, type) in zip(values(eval_env), variable_types.parameters)
        ]),
    )
end
