function gen_check_multiple_assignments_func(expr::Expr)
    logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays = extract_variables_assigned_to(
        expr
    )
    overlap_scalars = intersect(logical_scalars, stochastic_scalars)
    overlap_arrays = intersect(logical_arrays, stochastic_arrays)
    vars_to_unpack = extract_variables_used_in_bounds_and_indices(expr)
    return @q function __check_multiple_assignments(
        data::NamedTuple{data_keys,data_value_types},
        array_sizes::NamedTuple{array_vars,array_var_types},
    ) where {data_keys,data_value_types,array_vars,array_var_types}
        $(
            [
                Expr(:(=), Expr(:tuple, Expr(:parameters, vars_to_unpack...)), :data),
                (@q begin
                    __logical_arrays = $(logical_arrays)
                    __stochastic_arrays = $(stochastic_arrays)
                end).args...,
                @q(
                    __logical_assign_tracker = NamedTuple{__logical_arrays}(
                        Tuple([
                            JuliaBUGS.AssignmentTracker(var, array_sizes[var]) for
                            var in __logical_arrays
                        ]),
                    )
                ),
                @q(
                    __stochastic_assign_tracker = NamedTuple{__stochastic_arrays}(
                        Tuple([
                            JuliaBUGS.AssignmentTracker(var, array_sizes[var]) for
                            var in __stochastic_arrays
                        ]),
                    )
                )
            ]...
        )
        $(gen_check_multiple_assignments_func_main_body!(expr, Any[])...)

        bitmaps = Vector{BitArray}[$(gen_bitmap_ands(overlap_arrays)...)]

        return $overlap_scalars,
        NamedTuple{Tuple($overlap_arrays)}(
            Tuple(bitmaps),
        )
    end
end

@inline function gen_bitmap_ands(overlap_arrays::Vector{Symbol})
    return [
        @q(__logical_assign_tracker.$var.bitmap .& __stochastic_assign_tracker.$var.bitmap) for
        var in overlap_arrays
    ]
end

function gen_check_multiple_assignments_func_main_body!(expr::Expr, args::Vector{Any})
    for stmt in expr.args
        if @capture(stmt, lhs_ = rhs_)
            if lhs isa Symbol
                continue
            else
                push!(
                    args,
                    :(JuliaBUGS.set!(
                        __logical_assign_tracker.$(lhs.args[1]), $(lhs.args[2:end]...)
                    )),
                )
            end
        elseif @capture(stmt, lhs_ ~ rhs_)
            if lhs isa Symbol
                continue
            else
                push!(
                    args,
                    :(JuliaBUGS.set!(
                        __stochastic_assign_tracker.$(lhs.args[1]), $(lhs.args[2:end]...)
                    )),
                )
            end
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(
                args,
                @q(
                    for $loop_var in ($lower):($upper)
                        $(gen_check_multiple_assignments_func_main_body!(body, Any[])...)
                    end
                )
            )
        else
            push!(args, stmt) # TODO: return the original statement for debugging
        end
    end
    return args
end

# the LHS if assign to a array that's in data, if the type of the data array is concrete, then can skip

# also store the data:
# if the eltype of data array is concrete, then nothing happens
# if Missing is in eltype, then need to check, for now, store a bit array for the whole array

struct AssignmentTracker{name,N}
    bitmap::BitArray{N}
end

function AssignmentTracker(name, array_size::NTuple{N,Int}) where {N}
    bitmap = falses(array_size)
    return AssignmentTracker{name,N}(bitmap)
end

function set!(
    track_assigned::AssignmentTracker{name,N}, indices::Vararg{Int}
) where {name,N}
    if track_assigned.bitmap[indices...]
        throw(ArgumentError("$name already assigned"))
    end
    track_assigned.bitmap[indices...] = true
    return nothing
end

function set!(
    track_assigned::AssignmentTracker{name,N}, indices::Vararg{Union{Int,UnitRange{Int}}}
) where {name,N}
    if track_assigned.bitmap[indices...]
        throw(ArgumentError("$name already assigned"))
    end
    track_assigned.bitmap[indices...] .= true
    return nothing
end

function initialized_assign_tracker(
    vars::Tuple{Vararg{Symbol}}, array_sizes::NamedTuple{array_vars,array_types}
) where {array_vars,array_types}
    return NamedTuple{Tuple(vars)}(
        Tuple([AssignmentTracker(var, array_sizes[var]) for var in vars])
    )
end
