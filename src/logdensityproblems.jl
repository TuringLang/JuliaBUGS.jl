function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    vi, logp = evaluate!!(model, LogDensityContext(), x)
    return logp
end

function LogDensityProblems.dimension(model::AbstractBUGSModel)
    return if_transform ? model.transformed_param_length : model.untransformed_param_length
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
