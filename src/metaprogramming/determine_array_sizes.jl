using StaticArrays: StaticArrays
using MacroTools: prewalk, @capture, @q, postwalk

include("utils.jl")
include("extract_array_ndims.jl")

function gen_func(expr::Expr)
    #! format: off
    return @q function __determine_array_sizes(
        data::NamedTuple{names,types}
    ) where {names,types}
        $(gen_func_body(expr)...)
        return array_sizes
    end
    #! format: on
end

function gen_func_body(expr::Expr)
    args = []
    push!(args, gen_unpack(expr))
    push!(args, gen_array_sizes_init(expr)...)
    push!(args, gen_main_body(expr)...)
    return args
end

function gen_unpack(expr::Expr)
    vars_to_unpack = extract_variables_used_in_bounds_and_indices(expr)
    return Expr(:(=), Expr(:tuple, Expr(:parameters, vars_to_unpack...)), :data)
end

function gen_array_sizes_init(expr::Expr)
    array_ndims = extract_array_ndims(expr)
    names, args = Symbol[], Any[]
    for (var, dim) in pairs(array_ndims)
        if dim == 0
            continue
        end
        push!(names, var)
        push!(args, @q(_MVec{$dim}($(fill(1, dim)))))
    end
    return [
        @q(array_var_names = $(Tuple(names))),
        @q(array_sizes = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{array_var_names}(($(args...),))
        end),
        @q(
            for v in intersect(array_var_names, names)
                array_sizes[v] .= size(data[v])
            end
        )
    ]
end

function gen_main_body(expr::Expr)
    return gen_main_body_block!(expr, Any[])
end

function gen_main_body_block!(expr::Expr, args::Vector{Any})
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
                    $(gen_main_body_block!(body, Any[])...)
                end
            ))
        end
    end
    return args
end

function determine_array_sizes_logical!(
    data::NamedTuple{data_names,data_types},
    array_sizes::NamedTuple{names,types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_names,data_types,names,types,N}
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
    data::NamedTuple{data_names,data_types},
    array_sizes::NamedTuple{names,types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {data_names,data_types,names,types,N}
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
    ::NamedTuple{names,types}, var::Symbol
) where {names,types}
    return var in names
end
@inline function is_specified_by_data(
    data::NamedTuple{names,types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {names,types,N}
    if var ∉ names
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
    data::NamedTuple{names,types},
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int},N},
) where {names,types,N}
    if var ∉ names
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
