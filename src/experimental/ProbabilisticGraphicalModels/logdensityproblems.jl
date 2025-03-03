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
    evaluation_env = deepcopy(bn.evaluation_env)
    
    # Get all unobserved stochastic variables that need parameters
    unobserved_stochastic_vars = [
        bn.names[i] for i in bn.stochastic_ids 
        if !bn.is_observed[i]
    ]
    
    # Calculate dimensions for each variable
    total_dim = 0
    for vn in unobserved_stochastic_vars
        i = bn.names_to_ids[vn]
        dist = bn.distributions[i](evaluation_env, bn.loop_vars[vn])
        
        if transformed
            # Calculate transformed dimension
            b = Bijectors.bijector(dist)
            var_value = AbstractPPL.get(evaluation_env, vn)
            transformed_value = Bijectors.transform(b, var_value)
            total_dim += length(transformed_value)
        else
            # Calculate untransformed dimension
            var_value = AbstractPPL.get(evaluation_env, vn)
            total_dim += length(var_value)
        end
    end
    
    return total_dim
end

"""
    capabilities(::BayesianNetwork)

Return the differentiation capabilities of the BayesianNetwork.
"""
function LogDensityProblems.capabilities(::BayesianNetwork)
    return LogDensityProblems.LogDensityOrder{0}()
end
