struct DetermineArraySizes <: Analysis end

const __variables_in_data__ = gensym(:variables_in_data)
const __data__ = gensym(:data)

const __array_sizes__ = gensym(:array_sizes)
const __array_var_names__ = gensym(:array_var_names)

function generate_function_expr(
    analysis::DetermineArraySizes, expr::Expr, __source__::LineNumberNode
)
    variables_in_bounds_and_lhs_indices = extract_variables_in_bounds_and_lhs_indices(expr)
    array_ndims = extract_variable_names_and_numdims(expr)
    array_variables = [var for (var, ndims) in pairs(array_ndims) if ndims != 0]

    array_sizes_init_exprs = [
        @q(_MVec{$dim}($(fill(1, dim)))) for dim in values(array_ndims) if dim != 0
    ]

    return @q function __determine_array_sizes(
        $__data__::NamedTuple{$__variables_in_data__}
    ) where {$__variables_in_data__}
        map($(variables_in_bounds_and_lhs_indices)) do x
            if x ∉ $__variables_in_data__
                error(
                    "Variable `$x` is used in loop bounds or for indexing, but not provided by data.",
                )
            end
        end

        $(Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, variables_in_bounds_and_lhs_indices...)),
            __data__,
        ))
        $__array_var_names__ = $(Tuple(array_variables))
        $__array_sizes__ = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{$__array_var_names__}(($(array_sizes_init_exprs...),))
        end

        for v in intersect($__array_var_names__, $__variables_in_data__)
            $__array_sizes__[v] .= size(data[v])
        end

        $(generate_function_body(analysis, expr, __source__)...)
        return $(Tuple(keys(array_ndims))),
        NamedTuple{keys($__array_sizes__)}(Tuple.(values($__array_sizes__)))
    end
end

function generate_function_body(
    analysis::DetermineArraySizes, model_def::Expr, __source__::LineNumberNode
)
    args = Any[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(
                args,
                if lhs isa Symbol
                    @qq(
                        JuliaBUGS.determine_array_sizes_deterministic!(
                            data, $__array_sizes__, $(Meta.quot(lhs))
                        )
                    )
                else
                    @qq(
                        JuliaBUGS.determine_array_sizes_deterministic!(
                            data,
                            $__array_sizes__,
                            $(Meta.quot(lhs.args[1])),
                            $(lhs.args[2:end]...),
                        )
                    )
                end,
            )
        elseif @capture(statement, lhs_ ~ rhs_)
            push!(
                args,
                if lhs isa Symbol
                    nothing
                else
                    @qq(
                        JuliaBUGS.determine_array_sizes_stochastic!(
                            data,
                            $__array_sizes__,
                            $(Meta.quot(lhs.args[1])),
                            $(lhs.args[2:end]...),
                        )
                    )
                end,
            )
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(
                args,
                @q(
                    for $loop_var in ($lower):($upper)
                        $(generate_function_body(analysis, body, __source__)...)
                    end
                )
            )
        else
            push!(args, statement) # Debugging: don't change other type of statements
        end
    end
    return args
end

function determine_array_sizes_deterministic!(
    data::NamedTuple,
    array_sizes::NamedTuple,
    var::Symbol,
    indices::Vararg{__REAL_WITH_MISSING__},
)
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
    data::NamedTuple,
    array_sizes::NamedTuple,
    var::Symbol,
    indices::Vararg{Union{Missing,Float64,Int}},
)
    if is_partially_specified_as_data(data, var, indices...)
        throw(
            ArgumentError(
                "$var[$(join(indices, ", "))] partially observed, not allowed, rewrite so that the variables are either all observed or all unobserved.",
            ),
        )
    end
    return array_sizes[var] .= max.(array_sizes[var], indices)
end

@inline function is_specified_by_data(
    ::NamedTuple{data_keys}, var::Symbol
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        if data[var] isa AbstractArray
            throw(ArgumentError("In BUGS, implicit indexing on the LHS is not allowed."))
        end
    end
end
@inline function is_specified_by_data(
    data::NamedTuple{data_keys}, var::Symbol, indices::Vararg{Union{Missing,Float64,Int}}
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        if values isa AbstractArray
            if eltype(values) === Missing
                return false
            elseif eltype(values) <: __REAL__
                return true
            else
                return any(!ismissing, values)
            end
        else
            if values isa Missing
                return false
            elseif values <: __REAL__
                return true
            else
                error("Unexpected type: $(typeof(values))")
            end
        end
    end
end

@inline function is_partially_specified_as_data(
    data::NamedTuple{data_keys}, var::Symbol, indices::Vararg{Union{Missing,Float64,Int}}
) where {data_keys}
    if var ∉ data_keys
        return false
    else
        values = data[var][indices...]
        return values isa AbstractArray && any(ismissing, values) && any(!ismissing, values) 
    end
end
