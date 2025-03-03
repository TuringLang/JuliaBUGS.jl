"""
    logdensity(bn::BayesianNetwork, x::AbstractArray, model::AbstractBUGSModel)

Compute the log density of the BayesianNetwork given parameters x.
Requires the original BUGSModel to access transformed_var_lengths.
"""
function LogDensityProblems.logdensity(bn::BayesianNetwork, x::AbstractArray)
    _, logp = evaluate_with_values(bn, x)
    return logp
end

"""
    dimension(bn::BayesianNetwork, model::AbstractBUGSModel)

Return the dimension of the parameter space of the BayesianNetwork.
"""
function LogDensityProblems.dimension(bn::BayesianNetwork, model::AbstractBUGSModel)
    return if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end
end

"""
    capabilities(::BayesianNetwork)

Return the differentiation capabilities of the BayesianNetwork.
"""
function LogDensityProblems.capabilities(::BayesianNetwork)
    return LogDensityProblems.LogDensityOrder{0}()
end
