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
        node_function_fw = FunctionWrappers.FunctionWrapper{
            output_type,input_type
        }(
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

