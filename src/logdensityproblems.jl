function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    vi = evaluate!!(model, x)
    return DynamicPPL.getlogp(vi)
end

function LogDensityProblems.dimension(model::BUGSModel)
    return model.param_length
end

function LogDensityProblems.capabilities(::BUGSModel)
    return LogDensityProblems.LogDensityOrder{0}
end

# TODO: add these to package extension
# use with ReverseDiff
# using ReverseDiff
# using LogDensityProblemsAD
# p = ADgradient(:ReverseDiff, model; compile=Val(true))