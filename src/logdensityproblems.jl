function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    if model.has_generated_log_density_function
        @info "Using the generated log density function."
        return model.log_density_computation_function(model.evaluation_env, x)
    else
        _, logp = evaluate!!(model, x)
        return logp
    end
end

function LogDensityProblems.dimension(model::BUGSModel)
    return if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
