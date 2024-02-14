struct DetermineArraySizes <: Analysis end

function generate_analysis_function(analysis::DetermineArraySizes, expr::Expr)
    vars_to_unpack = extract_variables_used_in_bounds_and_indices(expr)
    array_ndims = extract_array_ndims(expr)
    arr_vars = [var for (var, dim) in pairs(array_ndims) if dim != 0]
    arr_sizes_init = [
        @q(_MVec{$dim}($(fill(1, dim)))) for dim in values(array_ndims) if dim != 0
    ]

    return @q function __determine_array_sizes(
        $__data__::NamedTuple{$__DATA_KEYS__,$__DATA_VALUE_TYPES__}
    ) where {$__DATA_KEYS__,$__DATA_VALUE_TYPES__}
        map($(vars_to_unpack)) do x
            if x ∉ $__DATA_KEYS__
                error(
                    "Variable `$x` is used in loop bounds or for indexing, but not provided by data.",
                )
            end
        end

        $(Expr(:(=), Expr(:tuple, Expr(:parameters, vars_to_unpack...)), __data__))
        $__array_var_names__ = $(Tuple(arr_vars))
        $__array_sizes__ = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{$__array_var_names__}(($(arr_sizes_init...),))
        end

        for v in intersect($__array_var_names__, $__DATA_KEYS__)
            $__array_sizes__[v] .= size(data[v])
        end

        $(generate_analysis_function_mainbody(analysis, expr)...)
        return $(Tuple(keys(array_ndims))), NamedTuple{keys($__array_sizes__)}(Tuple.(values($__array_sizes__)))
    end
end

function generate_analysis_function_statement_deterministic(
    ::DetermineArraySizes, lhs::Symbol, rhs::__RHS_UNION_TYPE__
)
    return @q(
        JuliaBUGS.determine_array_sizes_logical!(data, $__array_sizes__, $(Meta.quot(lhs)))
    )
end
function generate_analysis_function_statement_deterministic(
    ::DetermineArraySizes, lhs::Expr, rhs::__RHS_UNION_TYPE__
)
    return @q(
        JuliaBUGS.determine_array_sizes_logical!(
            data, $__array_sizes__, $(Meta.quot(lhs.args[1])), $(lhs.args[2:end]...)
        )
    )
end

function generate_analysis_function_statement_stochastic(
    ::DetermineArraySizes, lhs::Symbol, rhs::__RHS_UNION_TYPE__
)::Nothing
    return nothing
end
function generate_analysis_function_statement_stochastic(
    ::DetermineArraySizes, lhs::Expr, rhs::__RHS_UNION_TYPE__
)
    return @q(
        JuliaBUGS.determine_array_sizes_stochastic!(
            data, $__array_sizes__, $(Meta.quot(lhs.args[1])), $(lhs.args[2:end]...)
        )
    )
end

function determine_array_sizes_logical!(
    data::NamedTuple{data_keys,data_value_types},
    array_sizes::NamedTuple{array_vars,array_var_types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_keys,data_value_types,array_vars,array_var_types,N}
    if isempty(indices)
        if is_specified_by_data(data, var)
            throw(
                ArgumentError("Variable $var is specified by data, can't be assigned to.")
            )
        end
    else
        if is_specified_by_data(data, var, indices...)
            throw(
                ArgumentError(
                    "$var[$(join(indices, ", "))] is/are (partially) specified by data, can't be assigned to.",
                ),
            )
        end
        array_sizes[var] .= max.(array_sizes[var], indices)
    end
end

function determine_array_sizes_stochastic!(
    data::NamedTuple{data_keys,data_value_types},
    array_sizes::NamedTuple{array_vars,array_var_types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_keys,data_value_types,array_vars,array_var_types,N}
    if if_partially_specified_as_data(data, var, indices...)
        throw(
            ArgumentError(
                "$var[$(join(indices, ", "))] partially observed, not allowed, rewrite so that the variables are either all observed or all unobserved.",
            ),
        )
    end
    return array_sizes[var] .= max.(array_sizes[var], indices)
end

@inline function is_specified_by_data(
    data::NamedTuple{data_keys,data_value_types}, var::Symbol
) where {data_keys,data_value_types}
    return var in data_keys
end
@inline function is_specified_by_data(
    data::NamedTuple{data_keys,data_value_types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_keys,data_value_types,N}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        if values isa Missing
            return false
        elseif values <: Real
            return true
        elseif eltype(values) === Missing
            return false
        elseif eltype(values) <: Real
            return true
        else
            return any(!ismissing, values)
        end
    end
end

@inline function if_partially_specified_as_data(
    data::NamedTuple{data_keys,data_value_types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_keys,data_value_types,N}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        if isa(values, Missing) || isa(values, Real)
            return false
        elseif eltype(values) <: Real || eltype(values) === Missing
            return false
        else
            return any(ismissing, values) && any(!ismissing, values)
        end
    end
end
