struct CheckMultipleAssignments <: Analysis end

const __logical_assign_tracker__ = gensym(:logical_assign_tracker)
const __stochastic_assign_tracker__ = gensym(:stochastic_assign_tracker)

function generate_function_expr(
    analysis::CheckMultipleAssignments, expr::Expr, __source__::LineNumberNode
)
    logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays = extract_variables_assigned_to(
        expr
    )

    # repeating assignments within deterministic and stochastic scalars are checked `extract_variables_assigned_to``
    overlap_scalars = Tuple(intersect(logical_scalars, stochastic_scalars))
    overlap_arrays = intersect(logical_arrays, stochastic_arrays)
    variables_in_bounds_and_lhs_indices = extract_variables_in_bounds_and_lhs_indices(expr)

    __logical_arrays__ = gensym(:logical_arrays)
    __stochastic_arrays__ = gensym(:stochastic_arrays)
    __bitmaps__ = gensym(:bitmaps)

    return @q function __check_multiple_assignments(
        $__data__::NamedTuple, $__array_sizes__::NamedTuple
    )
        $(Expr(
            :(=),
            Expr(:tuple, Expr(:parameters, variables_in_bounds_and_lhs_indices...)),
            __data__,
        ))

        $__logical_arrays__ = $(logical_arrays)
        $__stochastic_arrays__ = $(stochastic_arrays)

        $__logical_assign_tracker__ = NamedTuple{$__logical_arrays__}(
            Tuple([
                JuliaBUGS.AssignmentTracker(var, $__array_sizes__[var]) for
                var in $__logical_arrays__
            ]),
        )
        $__stochastic_assign_tracker__ = NamedTuple{$__stochastic_arrays__}(
            Tuple([
                JuliaBUGS.AssignmentTracker(var, $__array_sizes__[var]) for
                var in $__stochastic_arrays__
            ]),
        )

        $(generate_function_body(analysis, expr, __source__)...)

        $__bitmaps__ = [$(gen_bitmap_ands(overlap_arrays)...)]
        return $overlap_scalars, NamedTuple{Tuple($overlap_arrays)}(Tuple($__bitmaps__))
    end
end

@inline function gen_bitmap_ands(overlap_arrays::Vector{Symbol})
    return [
        @q(
            $__logical_assign_tracker__.$var.bitmap .&
                $__stochastic_assign_tracker__.$var.bitmap
        ) for var in overlap_arrays
    ]
end

function generate_function_body(
    analysis::CheckMultipleAssignments, model_def::Expr, __source__::LineNumberNode
)
    args = Any[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            push!(
                args,
                if lhs isa Symbol
                    nothing
                else
                    @qq(
                        JuliaBUGS.set!(
                            $__logical_assign_tracker__.$(lhs.args[1]),
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
                        JuliaBUGS.set!(
                            $__stochastic_assign_tracker__.$(lhs.args[1]),
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
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(generate_function_body(analysis, body, __source__)...)
                end
            ))
        else
            push!(args, statement)
        end
    end
    return args
end

struct AssignmentTracker{name}
    bitmap::BitArray
end

function AssignmentTracker(name::Symbol, array_size::Tuple{Vararg{Int}})
    return AssignmentTracker{name}(falses(array_size))
end

function set!(
    track_assigned::AssignmentTracker{name}, indices::Vararg{Union{Int,UnitRange{Int}}}
) where {name}
    if any(track_assigned.bitmap[indices...])
        indices = Tuple(findall(track_assigned.bitmap[indices...]))
        throw(ArgumentError("$name already assigned at indices $indices"))
    end
    if eltype(indices) == Int
        track_assigned.bitmap[indices...] = true
    else
        track_assigned.bitmap[indices...] .= true
    end
end
