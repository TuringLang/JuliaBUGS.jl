function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    vi, logp = evaluate!!(model, LogDensityContext(), x)
    return logp
end

function LogDensityProblems.dimension(model::AbstractBUGSModel)
    return if model.if_transform
        model.transformed_param_length
    else
        model.untransformed_param_length
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
