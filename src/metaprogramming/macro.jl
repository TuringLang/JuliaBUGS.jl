using StaticArrays: StaticArrays
using MacroTools: prewalk, postwalk, @q, @qq

abstract type Analysis end

const __RHS_UNION_TYPE__ = Union{Int,Float64,Symbol,Expr}
const __REAL_WITH_MISSING__ = Union{Int,Float64,Missing}
const __REAL__ = Union{Int,Float64}

include("utils.jl")
include("determine_array_sizes.jl")
include("check_multiple_assignments.jl")

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

include("compute_transformed.jl")

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

include("loop_iterations.jl")

function count_num_vertices(model_def::Expr, bitmap::Vector{<:BitArray}, statement_counter::Ref{Int}=Ref(0))
    num_vertices = 0
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            num_vertices += sum(bitmap[statement_counter[]])
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            num_vertices += length(bitmap[statement_counter[]])
        elseif @capture(
            statement,
            for loop_var_ in loop_bounds_
                body_
            end
        )
            num_vertices += count_num_vertices(body, bitmap, statement_counter)
        else
            nothing
        end
    end
    return num_vertices
end

function initialize_statement_id_maps(eval_env::NamedTuple{var_names}) where {var_names}
    stmt_ids_arr = []
    for k in var_names
        if eval_env[k] isa AbstractArray
            # push!(stmt_ids_arr, zeros(UInt32, size(eval_env[k])...))
            push!(stmt_ids_arr, zeros(Int, size(eval_env[k])...))

        else
            push!(stmt_ids_arr, 0)
        end
    end
    return NamedTuple{var_names}(Tuple(stmt_ids_arr))
end

const __LOOP_ITER_BITMAP__ = gensym(:loop_iter_bitmap)

function specialize_model_def(model_def::Expr, bitmaps::Vector{<:BitArray})
    return Expr(:block, transform_expr_with_bitmaps(model_def, bitmaps, (), Ref(0))...)
end

function transform_expr_with_bitmaps(
    model_def::Expr,
    bitmaps::Vector{<:BitArray},
    loop_vars::Tuple{Vararg{Symbol}},
    statement_counter::Ref{Int},
)
    args = Expr[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            if lhs isa Symbol
                if only(bitmaps[statement_counter[]])
                    push!(args, statement)
                end
            else
                @capture(lhs, v_[is__])
                if all(bitmaps[statement_counter[]])
                    push!(args, statement)
                elseif !any(bitmaps[statement_counter[]])
                    nothing
                else
                    push!(args, @q if $__LOOP_ITER_BITMAP__[$(loop_vars...)]
                        $lhs = $rhs
                    end)
                end
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            if lhs isa Symbol
                if only(bitmaps[statement_counter[]])
                    push!(args, statement)
                else
                    push!(args, @q($lhs ≃ $rhs))
                end
            else
                @capture(lhs, v_[i__])
                if all(bitmaps[statement_counter[]])
                    push!(args, statement)
                elseif !any(bitmaps[statement_counter[]])
                    push!(args, @q($lhs ≃ $rhs))
                else
                    push!(args, @q if $__LOOP_ITER_BITMAP__[$(loop_vars...)]
                        $lhs ~ $rhs
                    else
                        $lhs ≃ $rhs
                    end)
                end
            end
        elseif @capture(
            statement,
            for loop_var_ in loop_bounds_
                body_
            end
        )
            loop_body = transform_expr_with_bitmaps(
                body, bitmaps, (loop_vars..., loop_var), statement_counter
            )
            if !isempty(loop_body)
                push!(args, @q(
                    for $loop_var in $loop_bounds
                        $(loop_body...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return args
end

include("build_graph.jl")

# function generate_function_body(analysis::Analysis, model_def::Expr, __source__::LineNumberNode)
#     args = Expr[]
#     for statement in model_def.args
#         if @capture(statement, lhs_ = rhs_)

#         elseif @capture(statement, lhs_ ~ rhs_)

#         elseif @capture(
#             statement,
#             for loop_var_ in lower_:upper_
#                 body_
#             end
#         )
#             push!(args, @q(
#                 for $loop_var in ($lower):($upper)
#                     $(generate_function_body(analysis, body, __source__)...)
#                 end
#             ))
#         else
#             push!(args, statement)
#         end
#     end
#     return args
# end
