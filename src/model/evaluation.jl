"""
    evaluate_with_rng!!(
        rng::Random.AbstractRNG, 
        model::BUGSModel; 
        sample_all=true, 
        temperature=1.0, 
        transformed=true
    )

Evaluate model using ancestral sampling from the given RNG.

# Arguments
- `rng`: Random number generator for sampling
- `model`: The BUGSModel to evaluate
- `sample_all`: If true, sample all variables; if false, only sample unobserved variables
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether to compute log density in transformed space (default true)

# Returns
- `evaluation_env`: Updated evaluation environment
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
"""
function evaluate_with_rng!!(
    rng::Random.AbstractRNG,
    model::BUGSModel;
    sample_all=true,
    temperature=1.0,
    transformed=true,
)
    logprior = 0.0
    loglikelihood = 0.0
    evaluation_env = deepcopy(model.evaluation_env)

    for (i, vn) in enumerate(model.graph_evaluation_data.sorted_nodes)
        is_stochastic = model.graph_evaluation_data.is_stochastic_vals[i]
        is_observed = model.graph_evaluation_data.is_observed_vals[i]
        node_function = model.graph_evaluation_data.node_function_vals[i]
        loop_vars = model.graph_evaluation_data.loop_vars_vals[i]
        if_sample = sample_all || !is_observed # also sample if not observed, only sample conditioned variables if sample_all is true

        if !is_stochastic
            value = node_function(evaluation_env, loop_vars)
            evaluation_env = setindex!!(evaluation_env, value, vn)
        else
            dist = node_function(evaluation_env, loop_vars)
            if if_sample
                value = rand(rng, dist) # just sample from the prior
            else
                value = AbstractPPL.get(evaluation_env, vn)
            end

            # Compute log density
            if transformed
                # see below for why we need to transform the value
                value_transformed = Bijectors.transform(Bijectors.bijector(dist), value)
                logp =
                    Distributions.logpdf(dist, value) + Bijectors.logabsdetjac(
                        Bijectors.inverse(Bijectors.bijector(dist)), value_transformed
                    )
            else
                logp = Distributions.logpdf(dist, value)
            end

            # Accumulate to appropriate component
            if is_observed
                loglikelihood += logp
            else
                logprior += logp
            end

            evaluation_env = setindex!!(evaluation_env, value, vn)
        end
    end

    return evaluation_env,
    (
        logprior=logprior,
        loglikelihood=loglikelihood,
        tempered_logjoint=logprior + temperature * loglikelihood,
    )
end

"""
    evaluate_with_env!!(
        model::BUGSModel; 
        temperature=1.0, 
        transformed=true
    )

Evaluate model using current values in the evaluation environment.

# Arguments
- `model`: The BUGSModel to evaluate
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether to compute log density in transformed space (default true)

# Returns
- `evaluation_env`: Updated evaluation environment
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
"""
function evaluate_with_env!!(model::BUGSModel; temperature=1.0, transformed=true)
    logprior = 0.0
    loglikelihood = 0.0
    evaluation_env = deepcopy(model.evaluation_env)

    for (i, vn) in enumerate(model.graph_evaluation_data.sorted_nodes)
        is_stochastic = model.graph_evaluation_data.is_stochastic_vals[i]
        is_observed = model.graph_evaluation_data.is_observed_vals[i]
        node_function = model.graph_evaluation_data.node_function_vals[i]
        loop_vars = model.graph_evaluation_data.loop_vars_vals[i]

        if !is_stochastic
            value = node_function(evaluation_env, loop_vars)
            evaluation_env = setindex!!(evaluation_env, value, vn)
        else
            dist = node_function(evaluation_env, loop_vars)
            value = AbstractPPL.get(evaluation_env, vn)

            if transformed
                # although the values stored in `evaluation_env` are in their original space, 
                # here we behave as accepting a vector of parameters in the transformed space
                # this is so that we have consistent logp values between
                # (1) set values in original space then evaluate (2) directly evaluate with the values in transformed space 
                value_transformed = Bijectors.transform(Bijectors.bijector(dist), value)
                logp =
                    Distributions.logpdf(dist, value) + Bijectors.logabsdetjac(
                        Bijectors.inverse(Bijectors.bijector(dist)), value_transformed
                    )
            else
                logp = Distributions.logpdf(dist, value)
            end

            # Accumulate to appropriate component
            if is_observed
                loglikelihood += logp
            else
                logprior += logp
            end
        end
    end

    return evaluation_env,
    (
        logprior=logprior,
        loglikelihood=loglikelihood,
        tempered_logjoint=logprior + temperature * loglikelihood,
    )
end

"""
    evaluate_with_values!!(
        model::BUGSModel, 
        flattened_values::AbstractVector; 
        temperature=1.0,
        transformed=true
    )

Evaluate model with the given parameter values.

# Arguments
- `model`: The BUGSModel to evaluate
- `flattened_values`: Vector of parameter values (in transformed or untransformed space)
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether the input values are in transformed space (default true)

# Returns
- `evaluation_env`: Updated evaluation environment
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
"""
function evaluate_with_values!!(
    model::BUGSModel, flattened_values::AbstractVector; temperature=1.0, transformed=true
)
    var_lengths = if transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    evaluation_env = deepcopy(model.evaluation_env)
    current_idx = 1
    logprior, loglikelihood = 0.0, 0.0
    for (i, vn) in enumerate(model.graph_evaluation_data.sorted_nodes)
        is_stochastic = model.graph_evaluation_data.is_stochastic_vals[i]
        is_observed = model.graph_evaluation_data.is_observed_vals[i]
        node_function = model.graph_evaluation_data.node_function_vals[i]
        loop_vars = model.graph_evaluation_data.loop_vars_vals[i]
        if !is_stochastic
            value = node_function(evaluation_env, loop_vars)
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        else
            dist = node_function(evaluation_env, loop_vars)
            if !is_observed
                l = var_lengths[vn]
                if transformed
                    b = Bijectors.bijector(dist)
                    b_inv = Bijectors.inverse(b)
                    reconstructed_value = reconstruct(
                        b_inv,
                        dist,
                        view(flattened_values, current_idx:(current_idx + l - 1)),
                    )
                    value, logjac = Bijectors.with_logabsdet_jacobian(
                        b_inv, reconstructed_value
                    )
                else
                    value = reconstruct(
                        dist, view(flattened_values, current_idx:(current_idx + l - 1))
                    )
                    logjac = 0.0
                end
                current_idx += l
                logprior += logpdf(dist, value) + logjac
                evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
            else
                loglikelihood += logpdf(dist, AbstractPPL.get(evaluation_env, vn))
            end
        end
    end
    return evaluation_env,
    (
        logprior=logprior,
        loglikelihood=loglikelihood,
        tempered_logjoint=logprior + temperature * loglikelihood,
    )
end
