using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using JuliaBUGS: generate_function_expr

using MacroTools, BangBang, Distributions
using JuliaBUGS.BUGSPrimitives

using JuliaBUGS:
    DetermineArraySizes,
    CheckMultipleAssignments,
    ComputeTransformed,
    LoopIteration,
    BuildGraph

using JuliaBUGS: initialize_vertex_id_map

using Graphs

model_def = deepcopy(leuk.model_def)
data = leuk.data;

##
f_expr = generate_function_expr(DetermineArraySizes(), model_def, LineNumberNode(0))
eval(f_expr)
all_vars, array_sizes = __determine_array_sizes(data)

f_expr = generate_function_expr(CheckMultipleAssignments(), model_def, LineNumberNode(0))
eval(f_expr)
potential_conflict = __check_multiple_assignments(data, array_sizes)

eval_env = JuliaBUGS.create_evaluate_env(all_vars, data, array_sizes)

f_expr = JuliaBUGS.generate_function_expr(
    ComputeTransformed(), model_def, LineNumberNode(0)
)
eval(f_expr)
eval_env = __compute_transformed!(eval_env)

JuliaBUGS.check_conflicts(eval_env, potential_conflict...)

eval_env = JuliaBUGS.concretize_eval_env_value_types(eval_env)

model_def = JuliaBUGS.loop_fission(model_def)

f_expr = generate_function_expr(LoopIteration(), model_def, eval_env)
eval(f_expr)
loop_iter_bitmaps = __compute_loop_iterations_bitmaps(eval_env)

f_expr = generate_function_expr(BuildGraph(), model_def, eval_env, loop_iter_bitmaps)
eval(f_expr)
vertex_id_map, g = __build_graph(eval_env, loop_iter_bitmaps, initialize_vertex_id_map(eval_env))

is_cyclic(g)

###################

const __loop_iter_bitmaps__ = gensym(:loop_iter_bitmap)

function specialize_model_def(model_def::Expr, bitmaps::Vector{<:BitArray})
    return Expr(:block, specialize_model_def(model_def, bitmaps, (), Ref(0))...)
end
function specialize_model_def(
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
                    push!(args, @q if $__loop_iter_bitmaps__[$(loop_vars...)]
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
                    push!(args, @q if $__loop_iter_bitmaps__[$(loop_vars...)]
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

function count_num_vertices(
    model_def::Expr, bitmap::Vector{<:BitArray}, statement_counter::Ref{Int}=Ref(0)
)
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
