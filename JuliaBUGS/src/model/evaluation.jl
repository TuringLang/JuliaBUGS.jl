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
        sample_observed=false,
        temperature=1.0,
        transformed=true,
    )

Evaluate model using ancestral sampling from the given RNG.

# Arguments
- `rng`: Random number generator for sampling
- `model`: The BUGSModel to evaluate
- `sample_observed`: If true, sample observed nodes; if false (default), keep observed data fixed at their data values. Latent variables are always sampled.
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether to compute log density in transformed space (default true)

# Returns
- `evaluation_env`: Updated evaluation environment
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
"""
function evaluate_with_rng!!(
    rng::Random.AbstractRNG,
    model::BUGSModel;
    sample_observed=false,
    temperature=1.0,
    transformed=true,
)
    logprior = 0.0
    loglikelihood = 0.0
    evaluation_env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)

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
            if is_observed
                if sample_observed
                    value = rand(rng, dist)
                else
                    value = AbstractPPL.getvalue(model.evaluation_env, vn)
                end
            else
                value = rand(rng, dist)
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

            # Only set value if we sampled it or if it's not observed
            # Observed values are already in evaluation_env from smart_copy_evaluation_env
            if !is_observed || sample_observed
                evaluation_env = setindex!!(evaluation_env, value, vn)
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
    function evaluate_with_env!!(
        model::BUGSModel,
        evaluation_env=smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols);
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
    evaluation_env=smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols);
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
            value = AbstractPPL.getvalue(evaluation_env, vn)

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

    evaluation_env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
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
                loglikelihood += logpdf(dist, AbstractPPL.getvalue(evaluation_env, vn))
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

# ======================
# Marginalization Support
# ======================

"""
    _is_discrete_finite_distribution(dist)

Check if a distribution is discrete with finite support.
"""
function _is_discrete_finite_distribution(dist)
    if !(dist isa Distributions.DiscreteUnivariateDistribution)
        return false
    end

    # Whitelist of known finite discrete distributions
    return dist isa Union{
        Distributions.Bernoulli,
        Distributions.Binomial,
        Distributions.Categorical,
        Distributions.DiscreteUniform,
        Distributions.BetaBinomial,
        Distributions.Hypergeometric,
    }
end

"""
    _enumerate_discrete_values(dist)

Return the finite support for a discrete univariate distribution.
Relies on Distributions.support to provide an iterable, finite range.
"""
_enumerate_discrete_values(dist::Distributions.DiscreteUnivariateDistribution) =
    Distributions.support(dist)

"""
    _classify_node_type(dist)

Classify a distribution into node types for marginalization.
Returns one of: :deterministic, :discrete_finite, :discrete_infinite, :continuous
"""
function _classify_node_type(dist)
    if _is_discrete_finite_distribution(dist)
        return :discrete_finite
    elseif dist isa Distributions.DiscreteUnivariateDistribution
        return :discrete_infinite
    else
        return :continuous
    end
end

"""
    _compute_node_types(model::BUGSModel)

Compute node type classification for all nodes in the model.
Returns a vector of symbols: `:deterministic`, `:discrete_finite`, `:discrete_infinite`, or `:continuous`.
"""
function _compute_node_types(model::BUGSModel)
    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)
    node_types = Vector{Symbol}(undef, n)

    for i in eachindex(gd.sorted_nodes)
        if !gd.is_stochastic_vals[i]
            node_types[i] = :deterministic
        else
            # Use invokelatest to avoid world age issues with runtime-generated functions
            dist = Base.invokelatest(
                gd.node_function_vals[i], model.evaluation_env, gd.loop_vars_vals[i]
            )
            node_types[i] = _classify_node_type(dist)
        end
    end

    return node_types
end

"""
    _get_stochastic_parents_indices(model::BUGSModel)

Get the stochastic parents (through deterministic nodes) for each node in the model.
Returns a vector of index vectors aligned with sorted_nodes.
"""
function _get_stochastic_parents_indices(model::BUGSModel)
    order = model.graph_evaluation_data.sorted_nodes
    name_to_pos = Dict(order[i] => i for i in 1:length(order))
    is_stochastic = model.graph_evaluation_data.is_stochastic_vals
    parents_idx = [Int[] for _ in 1:length(order)]

    for i in eachindex(order)
        if is_stochastic[i]
            # Use existing function to find stochastic parents through deterministic nodes
            stochastic_parents, _ = JuliaBUGS.dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
                model.g, order[i], MetaGraphsNext.inneighbor_labels
            )
            # Convert VarNames to indices
            for parent_vn in stochastic_parents
                if haskey(name_to_pos, parent_vn)
                    push!(parents_idx[i], name_to_pos[parent_vn])
                end
            end
            sort!(parents_idx[i])  # Keep sorted for stability
        end
    end

    return parents_idx
end

"""
    _precompute_minimal_cache_keys(model, order, node_types, stochastic_parents)

Precompute minimal cache keys for memoization during marginalization.

For each node, the frontier includes discrete finite variables that:
1. Were processed earlier in the evaluation order
2. Have dependents still to be processed (i.e., are still "live")
"""
function _precompute_minimal_cache_keys(
    model::BUGSModel,
    order::Vector{Int},
    node_types::Vector{Symbol},
    stochastic_parents::Vector{Vector{Int}},
)
    gd = model.graph_evaluation_data
    n = length(order)
    is_observed = gd.is_observed_vals

    # Map: node label → position in evaluation order
    label_to_pos = Vector{Int}(undef, n)
    @inbounds for pos in 1:n
        label_to_pos[order[pos]] = pos
    end

    # Compute last-use position for each unobserved discrete finite variable.
    # A variable is "live" until all stochastic nodes depending on it are processed.
    last_use_pos = Dict{Int,Int}()
    for node_label in 1:n
        if gd.is_stochastic_vals[node_label]
            node_pos = label_to_pos[node_label]
            for parent_label in stochastic_parents[node_label]
                if node_types[parent_label] == :discrete_finite &&
                    !is_observed[parent_label]
                    last_use_pos[parent_label] = max(
                        get(last_use_pos, parent_label, label_to_pos[parent_label]),
                        node_pos,
                    )
                end
            end
        end
    end

    # Map: position → discrete finite variables that start at that position
    starts_at_pos = Dict{Int,Vector{Int}}()
    for label in 1:n
        if node_types[label] == :discrete_finite && !is_observed[label]
            pos = label_to_pos[label]
            push!(get!(starts_at_pos, pos, Int[]), label)
        end
    end

    # Build frontier incrementally: at position k, include variables from positions < k
    # that are still live (last_use_pos >= k)
    minimal_keys = Dict{Int,Vector{Int}}()
    active = Int[]

    for pos in 1:n
        # Add variables processed at previous position (so they count as "earlier")
        if haskey(starts_at_pos, pos - 1)
            append!(active, starts_at_pos[pos - 1])
        end
        # Remove expired variables
        filter!(label -> get(last_use_pos, label, 0) >= pos, active)
        # Sort for stable memo keys
        sort!(active)
        minimal_keys[order[pos]] = copy(active)
    end

    return minimal_keys
end

"""
    _compute_marginalization_order(model, node_types, stochastic_parents)

Compute a topologically-valid evaluation order that reduces the frontier size
by placing discrete finite variables immediately before their observed dependents.

The heuristic iterates over observed nodes and places each node's discrete finite
parents right before it. This keeps discrete variables in the frontier briefly.
For models with shared discrete variables, more sophisticated ordering (e.g.,
min-degree) could further reduce frontier size, but this is NP-hard in general.
"""
function _compute_marginalization_order(
    model::BUGSModel, node_types::Vector{Symbol}, stochastic_parents::Vector{Vector{Int}}
)
    gd = model.graph_evaluation_data
    sorted_nodes = gd.sorted_nodes
    n = length(sorted_nodes)

    vn_to_idx = Dict(sorted_nodes[i] => i for i in 1:n)
    placed = fill(false, n)
    result = Int[]

    # Recursive placer: ensures all graph parents are placed before this node
    function place_with_deps(vn::VarName)
        idx = vn_to_idx[vn]
        placed[idx] && return nothing
        for parent_vn in MetaGraphsNext.inneighbor_labels(model.g, vn)
            place_with_deps(parent_vn)
        end
        push!(result, idx)
        placed[idx] = true
    end

    # For each observed node, place its discrete-finite parents immediately before it
    for (idx, vn) in enumerate(sorted_nodes)
        if gd.is_stochastic_vals[idx] && gd.is_observed_vals[idx]
            for parent_idx in stochastic_parents[idx]
                if node_types[parent_idx] == :discrete_finite &&
                    !gd.is_observed_vals[parent_idx]
                    place_with_deps(sorted_nodes[parent_idx])
                end
            end
            place_with_deps(vn)
        end
    end

    # Place any remaining nodes
    for vn in sorted_nodes
        place_with_deps(vn)
    end

    return result
end

"""
    _marginalize_recursive(model, env, remaining_indices, parameter_values,
                           param_offsets, var_lengths, memo, minimal_keys)

Recursively compute log probability by marginalizing over discrete finite variables.

Returns `(log_prior, log_lik)` where the total log joint is `log_prior + log_lik`.
This separation allows for likelihood tempering.
"""
function _marginalize_recursive(
    model::BUGSModel,
    env::NamedTuple,
    remaining_indices::AbstractVector{Int},
    parameter_values::AbstractVector{T},
    param_offsets::Dict{VarName,Int},
    var_lengths::Dict{VarName,Int},
    memo::Dict{Tuple{Int,Tuple},Tuple{T,T}},
    minimal_keys::Dict{Int,Vector{Int}},
) where {T}
    # Base case - use zero(T) for AD compatibility
    isempty(remaining_indices) && return (zero(T), zero(T))

    gd = model.graph_evaluation_data
    mc = model.marginalization_cache

    current_idx = remaining_indices[1]
    current_vn = gd.sorted_nodes[current_idx]

    # Memo key: (node index, frontier values)
    # Frontier indices are deterministic given current_idx, so only values needed
    frontier_indices = get(minimal_keys, current_idx, Int[])
    frontier_values = if isempty(frontier_indices)
        ()
    else
        Tuple(AbstractPPL.getvalue(env, gd.sorted_nodes[idx]) for idx in frontier_indices)
    end
    memo_key = (current_idx, frontier_values)

    haskey(memo, memo_key) && return memo[memo_key]

    node_function = gd.node_function_vals[current_idx]
    loop_vars = gd.loop_vars_vals[current_idx]
    rest_indices = @view(remaining_indices[2:end])

    result = if !gd.is_stochastic_vals[current_idx]
        # Deterministic node: compute value and continue
        value = node_function(env, loop_vars)
        new_env = BangBang.setindex!!(env, value, current_vn)
        _marginalize_recursive(
            model,
            new_env,
            rest_indices,
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )

    elseif gd.is_observed_vals[current_idx]
        # Observed stochastic node: add to likelihood
        dist = node_function(env, loop_vars)
        obs_value = AbstractPPL.getvalue(env, current_vn)
        obs_logp = logpdf(dist, obs_value)
        obs_logp = isnan(obs_logp) ? -Inf : obs_logp

        rest_prior, rest_lik = _marginalize_recursive(
            model,
            env,
            rest_indices,
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )
        (rest_prior, obs_logp + rest_lik)

    elseif mc.node_types[current_idx] == :discrete_finite
        # Discrete finite unobserved: marginalize by enumerating all values
        dist = node_function(env, loop_vars)
        possible_values = _enumerate_discrete_values(dist)

        # Lazy allocation for type stability with AD
        log_priors = nothing
        log_liks = nothing

        for (i, val) in enumerate(possible_values)
            branch_env = BangBang.setindex!!(env, val, current_vn)
            val_logp = logpdf(dist, val)
            val_logp = isnan(val_logp) ? -Inf : val_logp

            branch_prior, branch_lik = _marginalize_recursive(
                model,
                branch_env,
                rest_indices,
                parameter_values,
                param_offsets,
                var_lengths,
                memo,
                minimal_keys,
            )

            # log P(z=val, rest_prior)
            total_prior = val_logp + branch_prior
            if log_priors === nothing
                log_priors = Vector{typeof(total_prior)}(undef, length(possible_values))
                log_liks = Vector{typeof(branch_lik)}(undef, length(possible_values))
            end
            log_priors[i] = total_prior
            log_liks[i] = branch_lik
        end

        # Marginalize: sum over all discrete values
        # log_prior_marg = log Σ_z P(z, rest_prior)
        # log_joint_marg = log Σ_z P(z, rest_prior, data)
        log_prior_marg = LogExpFunctions.logsumexp(log_priors)
        log_joint_marg = LogExpFunctions.logsumexp(log_priors .+ log_liks)

        # log_lik = log P(data | params) = log_joint - log_prior
        log_lik_marg =
            isfinite(log_prior_marg) ? log_joint_marg - log_prior_marg : log_joint_marg
        (log_prior_marg, log_lik_marg)

    else
        # Continuous or discrete-infinite unobserved: read from parameter vector
        dist = node_function(env, loop_vars)
        bijector = Bijectors.bijector(dist)

        len = var_lengths[current_vn]
        start_idx = param_offsets[current_vn]
        param_slice = view(parameter_values, start_idx:(start_idx + len - 1))

        b_inv = Bijectors.inverse(bijector)
        reconstructed = reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed)

        new_env = BangBang.setindex!!(env, value, current_vn)

        dist_logp = logpdf(dist, value)
        dist_logp = isnan(dist_logp) ? -Inf : dist_logp + logjac

        rest_prior, rest_lik = _marginalize_recursive(
            model,
            new_env,
            rest_indices,
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )
        (dist_logp + rest_prior, rest_lik)
    end

    memo[memo_key] = result
    return result
end

"""
    evaluate_with_marginalization_values!!(model, flattened_values; temperature=1.0)

Evaluate model with marginalization over discrete finite variables.

This is the main entry point for auto-marginalization. Discrete finite variables are
summed out, while continuous parameters are read from `flattened_values` (which must
be in transformed/unconstrained space).
"""
function evaluate_with_marginalization_values!!(
    model::BUGSModel, flattened_values::AbstractVector; temperature=1.0
)
    mc = model.marginalization_cache
    if isnothing(mc)
        error(
            "Auto marginalization cache missing. " *
            "Call set_evaluation_mode(model, UseAutoMarginalization()) first.",
        )
    end

    # Initialize memoization cache with size hint
    # Use element type of parameter vector for AD compatibility (Float64 or Dual)
    T = eltype(flattened_values)
    n_nodes = length(model.graph_evaluation_data.sorted_nodes)
    expected_entries = if mc.n_discrete_finite > 20
        1_000_000
    else
        min((1 << mc.n_discrete_finite) * n_nodes, 1_000_000)
    end
    memo = Dict{Tuple{Int,Tuple},Tuple{T,T}}()
    sizehint!(memo, expected_entries)

    evaluation_env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)

    log_prior, log_likelihood = _marginalize_recursive(
        model,
        evaluation_env,
        mc.marginalization_order,
        flattened_values,
        mc.param_offsets,
        mc.param_lengths,
        memo,
        mc.minimal_cache_keys,
    )

    return evaluation_env,
    (
        logprior=log_prior,
        loglikelihood=log_likelihood,
        tempered_logjoint=log_prior + temperature * log_likelihood,
    )
end
