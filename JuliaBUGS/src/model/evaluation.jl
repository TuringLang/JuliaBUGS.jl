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
    evaluation_env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)

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

# ======================
# Marginalization Support
# ======================

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
    _precompute_minimal_cache_keys(model::BUGSModel, order::Vector{Int})

Precompute minimal cache keys for memoization during marginalization.
The frontier at each position should include all discrete finite variables that:
1. Have been processed (appear earlier in the evaluation order)
2. May affect the current computation
"""
function _precompute_minimal_cache_keys(model::BUGSModel, order::Vector{Int})
    gd = model.graph_evaluation_data
    n = length(order)
    is_stochastic = gd.is_stochastic_vals
    is_observed = gd.is_observed_vals
    is_discrete_finite = gd.is_discrete_finite_vals
    node_types = gd.node_types

    # Get stochastic parents (stochastic boundary) for each node
    parents_idx = _get_stochastic_parents_indices(model)

    # Build mapping from node index (in gd.sorted_nodes) -> position in the provided order.
    # This lets us reason about liveness w.r.t. the chosen evaluation order.
    order_pos = Vector{Int}(undef, length(gd.sorted_nodes))
    @inbounds for k in 1:n
        order_pos[order[k]] = k
    end

    # Compute last-use POSITIONS (w.r.t. 'order') for each unobserved finite-discrete variable.
    # A variable stays in the frontier until we pass the last stochastic node
    # (observed or unobserved) whose distribution depends on it.
    last_use_pos = Dict{Int,Int}()  # map from variable index -> last position in 'order'
    for j_label in 1:length(gd.sorted_nodes)
        if gd.is_stochastic_vals[j_label]
            j_pos = order_pos[j_label]
            for p_label in parents_idx[j_label]
                if is_discrete_finite[p_label] && !is_observed[p_label]
                    # Default to the position of the variable itself if unseen
                    default_pos = order_pos[p_label]
                    last_use_pos[p_label] = max(
                        get(last_use_pos, p_label, default_pos), j_pos
                    )
                end
            end
        end
    end

    # Initialize frontier keys for each position based on liveness
    # Optimized incremental construction to avoid O(n^2) in common patterns
    minimal_keys = Dict{Int,Vector{Int}}()

    # Precompute starts and ends in order positions
    starts_at = Dict{Int,Vector{Int}}()
    for lbl in 1:length(gd.sorted_nodes)
        pos = order_pos[lbl]
        if is_discrete_finite[lbl] && !is_observed[lbl]
            push!(get!(starts_at, pos, Int[]), lbl)
        end
    end

    # Active set of earlier discrete finite variables (by label index)
    active = Int[]
    # Track end positions for active labels
    function purge_expired!(active_vec::Vector{Int}, k_pos::Int)
        # Remove any with last_use_pos < k_pos
        i = 1
        while i <= length(active_vec)
            lbl = active_vec[i]
            if get(last_use_pos, lbl, 0) < k_pos
                deleteat!(active_vec, i)
            else
                i += 1
            end
        end
        return active_vec
    end

    for k in 1:n
        # Add labels that start at previous position so they count as "earlier"
        if haskey(starts_at, k - 1)
            append!(active, starts_at[k - 1])
        end
        # Drop any labels that have expired before current position
        purge_expired!(active, k)
        # Sort for stable key representation
        sort!(active)
        minimal_keys[order[k]] = copy(active)
    end

    return minimal_keys
end

"""
    _compute_marginalization_order(model::BUGSModel) -> Vector{Int}

Compute a topologically-valid evaluation order that reduces the frontier size
by placing discrete finite variables immediately before their observed dependents
whenever possible. This greatly reduces branching in the recursive enumerator.
"""
function _compute_marginalization_order(model::BUGSModel)
    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)

    # Mapping VarName <-> index in sorted_nodes
    order = gd.sorted_nodes
    pos = Dict(order[i] => i for i in 1:n)

    # Direct parents via graph (for topo validity)
    function parents(vn)
        return collect(MetaGraphsNext.inneighbor_labels(model.g, vn))
    end

    # Keep track of which nodes are placed
    placed = fill(false, n)
    out = Int[]

    # Recursive placer that ensures all parents are placed first
    function place_with_dependencies(vn::VarName)
        i = pos[vn]
        if placed[i]
            return nothing
        end
        # Place all direct parents first
        for p in parents(vn)
            place_with_dependencies(p)
        end
        push!(out, i)
        placed[i] = true
    end

    # Identify observed stochastic nodes and their discrete-finite parents (via stochastic boundary)
    # We use the existing helper to traverse through deterministic nodes
    stoch_parents = _get_stochastic_parents_indices(model)

    # First, for each observed stochastic node, place its discrete-finite parents
    # (and dependencies) immediately before placing the node itself.
    for (i, vn) in enumerate(order)
        if gd.is_stochastic_vals[i] && gd.is_observed_vals[i]
            # Place discrete-finite unobserved parents (by label index -> VarName)
            for pidx in stoch_parents[i]
                if gd.is_discrete_finite_vals[pidx] && !gd.is_observed_vals[pidx]
                    place_with_dependencies(order[pidx])
                end
            end
            # Then place the observed node itself (ensures mu/sigma/etc. also placed)
            place_with_dependencies(vn)
        end
    end

    # Finally, place any remaining nodes in topological order
    for vn in order
        if !placed[pos[vn]]
            place_with_dependencies(vn)
        end
    end

    return out
end

"""
    _marginalize_recursive(model, env, remaining_indices, parameter_values, param_idx, 
                          var_lengths, memo, minimal_keys)

Recursively compute log probability by marginalizing over discrete finite variables.
"""
function _marginalize_recursive(
    model::BUGSModel,
    env::NamedTuple,
    remaining_indices::AbstractVector{Int},
    parameter_values::AbstractVector,
    param_offsets::Dict{VarName,Int},
    var_lengths::Dict{VarName,Int},
    memo::Dict,
    minimal_keys,
)
    # Base case: no more nodes to process
    if isempty(remaining_indices)
        return zero(eltype(parameter_values))
    end

    current_idx = remaining_indices[1]
    current_vn = model.graph_evaluation_data.sorted_nodes[current_idx]

    # Create memo key using minimal frontier
    # Get the discrete finite frontier indices for this position (already sorted)
    discrete_frontier_indices = get(minimal_keys, current_idx, Int[])

    # Extract values only for discrete finite frontier variables
    if !isempty(discrete_frontier_indices)
        # These are discrete values set by enumeration, no AD wrapping
        frontier_values = [
            AbstractPPL.get(env, model.graph_evaluation_data.sorted_nodes[idx]) for
            idx in discrete_frontier_indices
        ]
        minimal_hash = hash((discrete_frontier_indices, frontier_values))
    else
        minimal_hash = UInt64(0)  # Empty frontier
    end
    # With parameter access keyed by variable name, results depend only on the
    # current node and the discrete frontier state. Continuous parameters are
    # global and constant for a given input vector.
    memo_key = (current_idx, minimal_hash)

    if haskey(memo, memo_key)
        return memo[memo_key]
    end

    is_stochastic = model.graph_evaluation_data.is_stochastic_vals[current_idx]
    is_observed = model.graph_evaluation_data.is_observed_vals[current_idx]
    is_discrete_finite = model.graph_evaluation_data.is_discrete_finite_vals[current_idx]
    node_function = model.graph_evaluation_data.node_function_vals[current_idx]
    loop_vars = model.graph_evaluation_data.loop_vars_vals[current_idx]

    if !is_stochastic
        # Deterministic node
        value = Base.invokelatest(node_function, env, loop_vars)
        new_env = BangBang.setindex!!(env, value, current_vn)
        result = _marginalize_recursive(
            model,
            new_env,
            @view(remaining_indices[2:end]),
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )

    elseif is_observed
        # Observed stochastic node
        dist = Base.invokelatest(node_function, env, loop_vars)
        obs_value = AbstractPPL.get(env, current_vn)
        obs_logp = logpdf(dist, obs_value)

        # Handle NaN values
        if isnan(obs_logp)
            obs_logp = -Inf
        end

        remaining_logp = _marginalize_recursive(
            model,
            env,
            @view(remaining_indices[2:end]),
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )
        result = obs_logp + remaining_logp

    elseif is_discrete_finite
        # Discrete finite unobserved node - marginalize out
        dist = Base.invokelatest(node_function, env, loop_vars)
        possible_values = enumerate_discrete_values(dist)

        logp_branches = Vector{typeof(zero(eltype(parameter_values)))}(
            undef, length(possible_values)
        )

        for (i, value) in enumerate(possible_values)
            branch_env = BangBang.setindex!!(env, value, current_vn)

            value_logp = logpdf(dist, value)
            if isnan(value_logp)
                value_logp = -Inf
            end

            remaining_logp = _marginalize_recursive(
                model,
                branch_env,
                @view(remaining_indices[2:end]),
                parameter_values,
                param_offsets,
                var_lengths,
                memo,
                minimal_keys,
            )

            logp_branches[i] = value_logp + remaining_logp
        end

        result = LogExpFunctions.logsumexp(logp_branches)

    else
        # Continuous or discrete infinite unobserved node - use parameter values
        dist = Base.invokelatest(node_function, env, loop_vars)
        b = Bijectors.bijector(dist)

        if !haskey(var_lengths, current_vn)
            error(
                "Missing transformed length for variable '$(current_vn)'. " *
                "All variables should have their transformed lengths pre-computed.",
            )
        end

        l = var_lengths[current_vn]
        # Fetch the start position for this variable from the precomputed map
        start_idx = get(param_offsets, current_vn, 0)
        if start_idx == 0
            error("Missing parameter offset for variable '$(current_vn)'.")
        end
        if start_idx + l - 1 > length(parameter_values)
            error(
                "Parameter index out of bounds: needed $(start_idx + l - 1) elements, " *
                "but parameter_values has only $(length(parameter_values)) elements.",
            )
        end

        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, start_idx:(start_idx + l - 1))

        reconstructed_value = reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)

        new_env = BangBang.setindex!!(env, value, current_vn)

        dist_logp = logpdf(dist, value)
        if isnan(dist_logp)
            dist_logp = -Inf
        else
            dist_logp += logjac
        end

        remaining_logp = _marginalize_recursive(
            model,
            new_env,
            @view(remaining_indices[2:end]),
            parameter_values,
            param_offsets,
            var_lengths,
            memo,
            minimal_keys,
        )

        result = dist_logp + remaining_logp
    end

    memo[memo_key] = result
    return result
end

"""
    evaluate_with_marginalization_rng!!(
        rng::Random.AbstractRNG, 
        model::BUGSModel; 
        temperature=1.0, 
        transformed=true
    )

Evaluate model using marginalization for discrete finite variables and sampling for others.
"""
function evaluate_with_marginalization_rng!!(
    rng::Random.AbstractRNG, model::BUGSModel; temperature=1.0, transformed=true
)
    if !transformed
        error(
            "Auto marginalization only supports transformed (unconstrained) parameter space. " *
            "Please use transformed=true.",
        )
    end

    # For RNG-based evaluation, we don't marginalize - we sample discrete variables
    # This is similar to evaluate_with_rng!! but could be extended for hybrid approaches
    return evaluate_with_rng!!(
        rng, model; sample_all=true, temperature=temperature, transformed=transformed
    )
end

"""
    evaluate_with_marginalization_env!!(
        model::BUGSModel,
        evaluation_env=smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols);
        temperature=1.0,
        transformed=true
    )

Evaluate model using marginalization for discrete finite variables.
"""
function evaluate_with_marginalization_env!!(
    model::BUGSModel,
    evaluation_env=smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols);
    temperature=1.0,
    transformed=true,
)
    if !transformed
        error(
            "Auto marginalization only supports transformed (unconstrained) parameter space. " *
            "Please use transformed=true.",
        )
    end

    # For environment-based evaluation without explicit parameter values,
    # we need to extract ONLY continuous parameters for marginalization
    gd = model.graph_evaluation_data
    param_values = Float64[]

    for vn in gd.sorted_parameters
        idx = findfirst(==(vn), gd.sorted_nodes)
        if idx !== nothing && gd.node_types[idx] == :continuous
            value = AbstractPPL.get(evaluation_env, vn)
            if transformed
                # Transform to unconstrained space
                (; node_function, loop_vars) = model.g[vn]
                dist = node_function(evaluation_env, loop_vars)
                transformed_value = Bijectors.transform(Bijectors.bijector(dist), value)
                if transformed_value isa AbstractArray
                    append!(param_values, vec(transformed_value))
                else
                    push!(param_values, transformed_value)
                end
            else
                if value isa AbstractArray
                    append!(param_values, vec(value))
                else
                    push!(param_values, value)
                end
            end
        end
    end

    return evaluate_with_marginalization_values!!(
        model, param_values; temperature=temperature, transformed=transformed
    )
end

"""
    evaluate_with_marginalization_values!!(
        model::BUGSModel, 
        flattened_values::AbstractVector; 
        temperature=1.0,
        transformed=true
    )

Evaluate model with marginalization over discrete finite variables.
"""
function evaluate_with_marginalization_values!!(
    model::BUGSModel, flattened_values::AbstractVector; temperature=1.0, transformed=true
)
    if !transformed
        error(
            "Auto marginalization only supports transformed (unconstrained) parameter space. " *
            "Please use transformed=true.",
        )
    end

    # Compute an order that minimizes frontier growth (interleave discrete parents before observed children)
    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)
    sorted_indices = _compute_marginalization_order(model)

    # Compute minimal cache keys for this specific order
    # (do not reuse cached keys if they were built for a different order)
    minimal_keys = _precompute_minimal_cache_keys(model, sorted_indices)

    # Initialize memoization cache
    # Size hint: at most 2^|discrete_finite| * |nodes| entries
    n_discrete_finite = sum(model.graph_evaluation_data.is_discrete_finite_vals)
    expected_entries = if n_discrete_finite > 20
        1_000_000  # Cap at 1M for large problems
    else
        min((1 << n_discrete_finite) * n, 1_000_000)
    end
    memo = Dict{Tuple{Int,UInt64},Any}()
    sizehint!(memo, expected_entries)

    # Start recursive evaluation
    evaluation_env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)

    # For marginalization, only continuous parameters need var_lengths
    # Discrete finite variables are marginalized over, not sampled
    var_lengths = Dict{VarName,Int}()
    continuous_param_order = VarName[]
    for vn in gd.sorted_parameters
        idx = findfirst(==(vn), gd.sorted_nodes)
        if idx !== nothing && gd.node_types[idx] == :continuous
            push!(continuous_param_order, vn)
            var_lengths[vn] = model.transformed_var_lengths[vn]
        end
    end

    # Build mapping from variable -> start index in flattened_values
    param_offsets = Dict{VarName,Int}()
    start = 1
    for vn in continuous_param_order
        param_offsets[vn] = start
        start += var_lengths[vn]
    end

    logp = _marginalize_recursive(
        model,
        evaluation_env,
        sorted_indices,
        flattened_values,
        param_offsets,
        var_lengths,
        memo,
        minimal_keys,
    )

    # For consistency with other evaluate functions, we return the environment
    # and split the log probability (though marginalization combines them)
    return evaluation_env,
    (
        logprior=logp,
        loglikelihood=0.0,  # Combined in logprior for marginalization
        tempered_logjoint=logp * temperature,
    )
end
