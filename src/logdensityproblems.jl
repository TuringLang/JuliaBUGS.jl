function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    vi, logp = evaluate!!(model, LogDensityContext(), x)
    return logp
end

function LogDensityProblems.dimension(model::AbstractBUGSModel)
    return if model.if_transform
        model.param_length[2]
    else
        model.param_length[1]
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
