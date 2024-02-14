struct CheckMultipleAssignments <: Analysis end

const __logical_arrays__ = gensym(:logical_arrays)
const __stochastic_arrays__ = gensym(:stochastic_arrays)

const __logical_assign_tracker__ = gensym(:logical_assign_tracker)
const __stochastic_assign_tracker__ = gensym(:stochastic_assign_tracker)

const __bitmaps__ = gensym(:bitmaps)
const __totoal_num_of_free_vars__ = gensym(:totoal_num_of_free_vars)

function generate_analysis_function(analysis::CheckMultipleAssignments, expr::Expr)
    logical_scalars, stochastic_scalars, logical_arrays, stochastic_arrays = extract_variables_assigned_to(
        expr
    )
    overlap_scalars = Tuple(intersect(logical_scalars, stochastic_scalars))
    overlap_arrays = intersect(logical_arrays, stochastic_arrays)
    vars_to_unpack = extract_variables_used_in_bounds_and_indices(expr)

    return @q function __check_multiple_assignments(
        $__data__::NamedTuple{$__DATA_KEYS__,$__DATA_VALUE_TYPES__},
        $__array_sizes__::NamedTuple{$__ARRAY_VARS__},
    ) where {$__DATA_KEYS__,$__DATA_VALUE_TYPES__,$__ARRAY_VARS__}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, vars_to_unpack...)), __data__))

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

        $(generate_analysis_function_mainbody!(analysis, expr)...)
        
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

function generate_analysis_function_statement_deterministic(
    ::CheckMultipleAssignments, ::Symbol, rhs::__RHS_UNION_TYPE__
)
    return nothing
end
function generate_analysis_function_statement_deterministic(
    ::CheckMultipleAssignments, lhs::Expr, rhs::__RHS_UNION_TYPE__
)
    return @q(
        JuliaBUGS.set!($__logical_assign_tracker__.$(lhs.args[1]), $(lhs.args[2:end]...))
    )
end

function generate_analysis_function_statement_stochastic(
    ::CheckMultipleAssignments, ::Symbol, rhs::__RHS_UNION_TYPE__
)
    return nothing
end
function generate_analysis_function_statement_stochastic(
    ::CheckMultipleAssignments, lhs::Expr, rhs::__RHS_UNION_TYPE__
)
    return @q(
        JuliaBUGS.set!($__stochastic_assign_tracker__.$(lhs.args[1]), $(lhs.args[2:end]...))
    )
end

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
