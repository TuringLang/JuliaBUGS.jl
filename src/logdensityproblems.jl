function LogDensityProblems.logdensity(
    model::BUGSModel{<:UseGeneratedLogDensityFunction}, x::AbstractArray
)
    return model.log_density_computation_function(model.evaluation_env, x)
end

function LogDensityProblems.logdensity(model::BUGSModel{<:UseGraph}, x::AbstractArray)
    _, logp = JuliaBUGS.evaluate!!(model, x)
    return logp
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
