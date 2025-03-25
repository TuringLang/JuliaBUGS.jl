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
    dimension(bn::BayesianNetwork)

Return the dimension of the parameter space of the BayesianNetwork.
"""
function LogDensityProblems.dimension(bn::BayesianNetwork)
    return bn.transformed_param_length
end

"""
    capabilities(::BayesianNetwork)

Return the differentiation capabilities of the BayesianNetwork.
"""
function LogDensityProblems.capabilities(::BayesianNetwork)
    return LogDensityProblems.LogDensityOrder{0}()
end
