function gen_deter_arr_sizes_func(expr::Expr)
    return @q function __determine_array_sizes(
        data::NamedTuple{$__DATA_KEYS__,$__DATA_VALUE_TYPES__}
    ) where {$__DATA_KEYS__,$__DATA_VALUE_TYPES__}
        $(gen_deter_arr_sizes_func_setup(expr)...)
        $(gen_deter_arr_sizes_func_main_body!(expr, Any[])...)
        return NamedTuple{keys(array_sizes)}(Tuple.(values(array_sizes)))
    end
end

function gen_deter_arr_sizes_func_setup(expr::Expr)
    vars_to_unpack = extract_variables_used_in_bounds_and_indices(expr)
    array_ndims = extract_array_ndims(expr)
    arr_vars = [var for (var, dim) in pairs(array_ndims) if dim != 0]
    arr_sizes_init = [
        @q(_MVec{$dim}($(fill(1, dim)))) for dim in values(array_ndims) if dim != 0
    ]
    return [
        @q(
            map($(vars_to_unpack)) do x
                if x ∉ $__DATA_KEYS__
                    error(
                        "Variable `$x` is used in loop bounds or for indexing, but not provided by data.",
                    )
                end
            end
        ),
        Expr(:(=), Expr(:tuple, Expr(:parameters, vars_to_unpack...)), :data),
        @q(__array_var_names = $(Tuple(arr_vars))),
        @q(array_sizes = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{__array_var_names}(($(arr_sizes_init...),))
        end),
        @q(
            for v in intersect(__array_var_names, $__DATA_KEYS__)
                array_sizes[v] .= size(data[v])
            end
        )
    ]
end

function gen_deter_arr_sizes_func_main_body!(expr::Expr, args::Vector{Any})
    for stmt in expr.args
        if @capture(stmt, lhs_ = rhs_)
            if lhs isa Symbol
                push!(
                    args,
                    :(JuliaBUGS.determine_array_sizes_logical!(
                        data, array_sizes, $(Meta.quot(lhs))
                    )),
                )
            else
                push!(
                    args,
                    :(JuliaBUGS.determine_array_sizes_logical!(
                        data, array_sizes, $(Meta.quot(lhs.args[1])), $(lhs.args[2:end]...)
                    )),
                )
            end
        elseif @capture(stmt, lhs_ ~ rhs_)
            if lhs isa Symbol
                continue
            else
                push!(
                    args,
                    :(JuliaBUGS.determine_array_sizes_stochastic!(
                        data, array_sizes, $(Meta.quot(lhs.args[1])), $(lhs.args[2:end]...)
                    )),
                )
            end
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(gen_deter_arr_sizes_func_main_body!(body, Any[])...)
                end
            ))
        else
            push!(args, stmt) # TODO: return the original statement for debugging
        end
    end
    return args
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
                "$var[$(join(indices, ", "))] partially observed, which is not allowed."
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
