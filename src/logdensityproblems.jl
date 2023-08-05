function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    vi = evaluate!!(model, LogDensityContext(x))
    return DynamicPPL.getlogp(vi)
end

function LogDensityProblems.dimension(model::BUGSModel)
    return model.param_length
end

function LogDensityProblems.capabilities(::BUGSModel)
    return LogDensityProblems.LogDensityOrder{0}
end
