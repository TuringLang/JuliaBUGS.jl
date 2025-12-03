using LogDensityProblems

function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    return model.log_density_computation_function(model.evaluation_env, x)
end

function _eval_logdensity(model, ::UseGraph, x)
    _, logp = AbstractPPL.evaluate!!(model, x)
    return logp
end

function _eval_logdensity(model, ::UseAutoMarginalization, x)
    _, log_densities = evaluate_with_marginalization_values!!(model, x; transformed=true)
    return log_densities.tempered_logjoint
end

function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    return _eval_logdensity(model, model.evaluation_mode, x)
end

function LogDensityProblems.dimension(model::BUGSModel)
    # For auto marginalization, only count continuous parameters
    if model.evaluation_mode isa UseAutoMarginalization
        mc = model.marginalization_cache
        continuous_param_length = 0
        for (i, vn) in enumerate(model.graph_evaluation_data.sorted_parameters)
            idx = findfirst(==(vn), model.graph_evaluation_data.sorted_nodes)
            if idx !== nothing
                node_type = mc.node_types[idx]
                # Only include continuous variables (exclude all discrete)
                if node_type == :continuous
                    if model.transformed
                        continuous_param_length += model.transformed_var_lengths[vn]
                    else
                        continuous_param_length += model.untransformed_var_lengths[vn]
                    end
                elseif node_type == :discrete_infinite
                    error(
                        "Model contains discrete infinite variable $(vn) which cannot be marginalized. " *
                        "Use UseGraph evaluation mode instead.",
                    )
                end
            end
        end
        return continuous_param_length
    else
        return if model.transformed
            model.transformed_param_length
        else
            model.untransformed_param_length
        end
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
