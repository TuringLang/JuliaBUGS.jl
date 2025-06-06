# Model Evaluation Functions
#
# This module provides three core evaluation functions for BUGSModel. The key design insight
# is that parameter values can come from different sources, requiring different evaluation strategies:
#
# 1. **evaluate_with_rng!!** - Parameters sampled from distributions
#    - Use case: Forward simulation, ancestral sampling
#    - Parameter source: Random sampling using provided RNG
#    - Example: Generating prior/posterior samples
#
# 2. **evaluate_with_env!!** - Parameters from current environment
#    - Use case: Log density evaluation at current parameter values, stateful computations
#    - Parameter source: Values already stored in model.evaluation_env (or custom env)
#    - Example: Computing log density for MCMC acceptance, maintaining state across evaluations
#
# 3. **evaluate_with_values!!** - Parameters from provided vector
#    - Use case: Optimization, gradient computation, external parameter sets
#    - Parameter source: Flattened parameter vector (transformed or untransformed space)
#    - Example: LogDensityProblems.jl interface, HMC sampling
#
# All functions return:
# - Updated evaluation environment with computed values
# - NamedTuple of log densities: (logprior, loglikelihood, tempered_logjoint)
#
# Common parameters:
# - `temperature`: Likelihood tempering factor (tempered_logjoint = logprior + temperature * loglikelihood)
# - `transformed`: Whether to work in transformed (unconstrained) parameter space

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
        if_sample = sample_all || !is_observed

        if !is_stochastic
            value = node_function(evaluation_env, loop_vars)
            evaluation_env = setindex!!(evaluation_env, value, vn)
        else
            dist = node_function(evaluation_env, loop_vars)
            if if_sample
                value = rand(rng, dist)
            else
                value = AbstractPPL.get(evaluation_env, vn)
            end

            if transformed
                value_transformed = Bijectors.transform(Bijectors.bijector(dist), value)
                logp =
                    Distributions.logpdf(dist, value) + Bijectors.logabsdetjac(
                        Bijectors.inverse(Bijectors.bijector(dist)), value_transformed
                    )
            else
                logp = Distributions.logpdf(dist, value)
            end

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
    function evaluate_with_env!!(
        model::BUGSModel,
        evaluation_env=deepcopy(model.evaluation_env);
        temperature=1.0,
        transformed=true,
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
function evaluate_with_env!!(
    model::BUGSModel,
    evaluation_env=deepcopy(model.evaluation_env);
    temperature=1.0,
    transformed=true,
)
    logprior = 0.0
    loglikelihood = 0.0

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
                # this is for consistency reasons
                value_transformed = Bijectors.transform(Bijectors.bijector(dist), value)
                logp =
                    Distributions.logpdf(dist, value) + Bijectors.logabsdetjac(
                        Bijectors.inverse(Bijectors.bijector(dist)), value_transformed
                    )
            else
                logp = Distributions.logpdf(dist, value)
            end

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
