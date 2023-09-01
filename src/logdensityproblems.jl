function LogDensityProblems.logdensity(model::AbstractBUGSModel, x::AbstractArray)
    vi = evaluate!!(model, LogDensityContext(), x)
    return DynamicPPL.getlogp(vi)
end

function LogDensityProblems.dimension(model::AbstractBUGSModel)
    return get_param_length(model)
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end
