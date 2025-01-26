function _return_node_function_and_exprs(model)
    node_functions_with_effect = Any[]
    node_functions_with_effect_exprs = Any[]
    node_functions_with_effect_function_wrapper = Any[]
    for vn in model.flattened_graph.sorted_nodes
        node_function_with_effect = g[vn].node_function_with_effect
        push!(node_functions_with_effects, node_function_with_effect)
        push!(node_functions_with_effects_exprs, node_function_with_effect)

        input_type = Tuple{
            eval_env_type,
            typeof(model.flattened_graph_node_data.loop_vars_vals[i]),
            typeof(vn),
            Bool,
            Bool,
            Vector{Float64},
        }
        output_type = Tuple{Float64,eval_env_type}
        node_function_fw = FunctionWrappers.FunctionWrapper{output_type,input_type}(
            node_function_with_effect
        )

        push!(node_functions_with_effect_function_wrapper, node_function_fw)
    end

    return node_functions_with_effect,
    node_functions_with_effect_exprs,
    map(identity, node_functions_with_effect_function_wrapper)
end

function _new_eval(
    model::BUGSModel{base_model_T,evaluation_env_T}, flattened_values::AbstractVector
) where {base_model_T,evaluation_env_T}
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    evaluation_env = deepcopy(model.evaluation_env)
    current_idx = 1
    logp = 0.0
    for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        node_function_with_effect = model.flattened_graph_node_data.node_function_with_effect_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]
        if !is_stochastic
            _, evaluation_env = node_function_with_effect(
                evaluation_env,
                loop_vars,
                vn,
                model.transformed,
                is_observed,
                zeros(eltype(flattened_values), 1),
            )
        else
            if !is_observed
                _logp, evaluation_env = node_function_with_effect(
                    evaluation_env,
                    loop_vars,
                    vn,
                    model.transformed,
                    is_observed,
                    flattened_values[current_idx:(current_idx + var_lengths[vn] - 1)],
                )
                logp += _logp
                current_idx += var_lengths[vn]
            else
                _logp, _ = node_function_with_effect(
                    evaluation_env,
                    loop_vars,
                    vn,
                    model.transformed,
                    is_observed,
                    Float64[], # not used
                )
                logp += _logp
            end
        end
    end
    return evaluation_env, logp
end

function _new_eval_with_function_wrapper(
    model::BUGSModel{base_model_T,evaluation_env_T},
    flattened_values::AbstractVector{Float64},
) where {base_model_T,evaluation_env_T}
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    evaluation_env = deepcopy(model.evaluation_env)

    eval_env_type = typeof(evaluation_env)

    current_idx = 1
    logp = 0.0
    for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        node_function_with_effect_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]
        if !is_stochastic
            evaluation_env = node_function_with_effect_fw(
                evaluation_env,
                loop_vars,
                vn,
                model.transformed,
                is_observed,
                zeros(eltype(flattened_values), 1),
            )[2]::eval_env_type
        else
            if !is_observed
                _logp, evaluation_env = node_function_with_effect_fw(
                    evaluation_env,
                    loop_vars,
                    vn,
                    model.transformed,
                    is_observed,
                    flattened_values[current_idx:(current_idx + var_lengths[vn] - 1)],
                )::Tuple{Float64,eval_env_type}
                logp += _logp
                current_idx += var_lengths[vn]
            else
                _logp = node_function_with_effect_fw(
                    evaluation_env,
                    loop_vars,
                    vn,
                    model.transformed,
                    is_observed,
                    Float64[], # not used
                )[1]::Float64
                logp += _logp
            end
        end
    end
    return evaluation_env, logp
end

model.g[@varname(Y[30, 5])].node_function_expr
model.g[@varname(var"beta.tau")].node_function_expr
###

# the input to node function can be two Tuples of Ints, the first one is the indices of the varname, the second one is the values of the loop_vars
# to make the type fully concrete, we need to find the max length of the indices and the loop_vars
# and for cases where the varname does not have indices, we need to fill the indices with 0s



# then the node function of Y[30, 5] would be
function Y_30_5(evaluation_env, loop_vars::NTuple{2, Int}, vn_indices::NTuple{2, Int}, flattened_values::AbstractVector{Float64}, start_idx::Int, end_idx::Int)
    (; mu, var"tau.c") = evaluation_env
    i = loop_vars[1]
    j = loop_vars[2]
    dist = JuliaBUGS.dnorm(mu[i, j], var"tau.c")
    # vn = VarName{:Y}(AbstractPPL.IndexLens(vn_indices))
    # value = AbstractPPL.get(evaluation_env, vn)
    value = evaluation_env.Y[vn_indices[1], vn_indices[2]]
    return evaluation_env, logpdf(dist, value)
end

@code_warntype Y_30_5(evaluation_env, (30, 5), (30, 5), rand_params, 0, 0)

@benchmark Y_30_5($evaluation_env, (30, 5), (30, 5), $rand_params, 0, 0)

# beta.tau
function beta_tau(evaluation_env, loop_vars::NTuple{2, Int}, vn_indices::NTuple{2, Int}, flattened_values::Vector{Float64}, start_idx::Int, end_idx::Int)
    (;) = evaluation_env
    dist = JuliaBUGS.dgamma(0.001, 0.001)
    b = Bijectors.bijector(dist)
    b_inv = Bijectors.inverse(b)
    reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, view(flattened_values, start_idx:end_idx))
    value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)
    logprior = logpdf(dist, value) + logjac
    vn = VarName{Symbol("beta.tau")}(identity)
    evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
    return evaluation_env, logprior
end

@benchmark beta_tau($evaluation_env, (0, 0), (0, 0), $rand_params, 1, 1)

# now we write the code to creates these node functions
# there are several components to this task:
current_nf = model.g[@varname(Y[30, 5])].node_function_expr
_value_unpack_expr = current_nf.args[2].args[1]
_loop_var_unpack_expr = current_nf.args[2].args[2]

using MacroTools
# turn _loop_var_unpack_expr from `loop_vars::NamedTuple` to from `loop_vars::NTuple{2, Int}`
function turn_loop_var_unpack_expr_to_ntuple(expr, N_loop_vars)
    expr = deepcopy(expr)
    @show expr
    loop_vars_syms = expr.args[1].args[1].args
    loop_vars_syms_sorted = sort(loop_vars_syms)

    if length(loop_vars_syms_sorted) == N_loop_vars
        expr.args[1].args[1].args = loop_vars_syms_sorted
    else
        expr.args[1].args[1].args = push!(loop_vars_syms_sorted, :_) # add a dummy variable to catch the don't-cares 
    end

    return expr
end

turn_loop_var_unpack_expr_to_ntuple(_loop_var_unpack_expr, 2)

_return_expr = current_nf.args[2].args[3] |> dump
# next, capture the return of the original node function
function _capture_return_of_original_node_function(expr, if_stochastic)
    expr = deepcopy(expr)
    comp_expr = expr.args[1]
    if if_stochastic
        return Expr(:(=), :__dist__, comp_expr)
    else
        return Expr(:(=), :__value__, comp_expr)
    end
end

model.g[@varname(mu[30, 5])].node_function_expr

function _gen_loop_var_unpack_expr(expr, N_loop_vars)
    loop_vars_syms = expr.args[1].args[1].args
    loop_vars_syms_sorted = sort(loop_vars_syms)
    if length(loop_vars_syms_sorted) == 0
        return nothing
    elseif length(loop_vars_syms_sorted) == N_loop_vars
        new_expr = deepcopy(expr.args[1].args[1])
        new_expr.args = loop_vars_syms_sorted
        return new_expr
    else
        push!(loop_vars_syms_sorted, :_)  # dummy to catch don't-cares
        new_expr = deepcopy(expr.args[1].args[1])
        new_expr.args = loop_vars_syms_sorted
        return new_expr
    end
end

_gen_loop_var_unpack_expr(:((;i) = env), 2)

@code_warntype y_30_5_func(evaluation_env, loop_vars, vn_indices, flattened_values, 0, 0)
@benchmark $y_30_5_func($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 0, 0)

@code_warntype Y_30_5(evaluation_env, loop_vars, vn_indices, flattened_values, 0, 0)
@benchmark Y_30_5($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 0, 0)