"""
    condition(bn::BayesianNetwork{V}, values::Dict{V,Any}) where {V}

Condition the Bayesian Network on the values of some variables. Return a new Bayesian Network with the conditioned graph.
"""
function condition(
    bn::BayesianNetwork{V}, conditioning_variables_and_values::Dict{V,<:Any}
) where {V}
    is_observed = copy(bn.is_observed)
    values = copy(bn.values)
    bn_new = BangBang.setproperties!!(bn; is_observed=is_observed, values=values)
    return condition!(bn_new, conditioning_variables_and_values)
end

"""
    condition!(bn::BayesianNetwork{V}, values::Dict{V,Any}) where {V}

Condition the Bayesian Network on the values of some variables. Mutating version of [`condition`](@ref).
"""
function condition!(
    bn::BayesianNetwork{V}, conditioning_variables_and_values::Dict{V,<:Any}
) where {V}
    for (name, value) in conditioning_variables_and_values
        id = bn.names_to_ids[name]
        if !bn.is_stochastic[id]
            throw(ArgumentError("Variable $name is not stochastic, cannot condition on it"))
        elseif bn.is_observed[id]
            @warn "Variable $name is already observed, overwriting its value"
        else
            bn.is_observed[id] = true
        end
        bn.values[name] = value
    end
    return bn
end

function decondition(bn::BayesianNetwork{V}) where {V}
    conditioned_variables_ids = findall(bn.is_observed)
    return decondition(bn, bn.names[conditioned_variables_ids])
end

function decondition!(bn::BayesianNetwork{V}) where {V}
    conditioned_variables_ids = findall(bn.is_observed)
    return decondition!(bn, bn.names[conditioned_variables_ids])
end

function decondition(bn::BayesianNetwork{V}, variables::Vector{V}) where {V}
    is_observed = copy(bn.is_observed)
    values = copy(bn.values)
    bn_new = BangBang.setproperties!!(bn; is_observed=is_observed, values=values)
    return decondition!(bn_new, variables)
end

function decondition!(bn::BayesianNetwork{V}, deconditioning_variables::Vector{V}) where {V}
    for name in deconditioning_variables
        id = bn.names_to_ids[name]
        if !bn.is_stochastic[id]
            throw(
                ArgumentError("Variable $name is not stochastic, cannot decondition on it")
            )
        elseif !bn.is_observed[id]
            throw(ArgumentError("Variable $name is not observed, cannot decondition on it"))
        end
        bn.is_observed[id] = false
        delete!(bn.values, name)
    end
    return bn
end
