function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    vi, logp = evaluate!!(model, LogDensityContext(), x)
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
