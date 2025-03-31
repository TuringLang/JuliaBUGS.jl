function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    return model.log_density_computation_function(model.evaluation_env, x)
end

function _eval_logdensity(model, ::UseGraph, x)
    _, logp = JuliaBUGS.evaluate!!(model, x)
    return logp
end

function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    return _eval_logdensity(model, model.evaluation_mode, x)
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
