"""
	BayesianNetwork

A structure representing a Bayesian Network.
"""
struct BayesianNetwork{V,T,F}
    graph::SimpleDiGraph{T}
    "names of the variables in the network"
    names::Vector{V}
    "mapping from variable names to ids"
    names_to_ids::Dict{V,T}
    "values of each variable in the network"
    evaluation_env::NamedTuple
    loop_vars::Dict{V,NamedTuple}
    "distributions of the stochastic variables"
    distributions::Vector{F}
    "deterministic functions of the deterministic variables"
    deterministic_functions::Vector{F}
    "ids of the stochastic variables"
    stochastic_ids::Vector{T}
    "ids of the deterministic variables"
    deterministic_ids::Vector{T}
    is_stochastic::BitVector
    is_observed::BitVector
    node_types::Vector{Symbol}            # e.g. :discrete or :continuous
    "transformed variable lengths for each variable"
    transformed_var_lengths::Dict{V,Int}
    "total length of transformed parameters"
    transformed_param_length::Int
end

function BayesianNetwork{V}() where {V}
    return BayesianNetwork(
        SimpleDiGraph{Int}(), # by default, vertex ids are integers
        V[],
        Dict{V,Int}(),
        (;),    # Empty NamedTuple for evaluation_env
        Dict{V,NamedTuple}(),
        Any[],
        Any[],
        Int[],
        Int[],
        BitVector(),
        BitVector(),
        Symbol[],
        Dict{V,Int}(),  # Empty Dict for transformed_var_lengths
        0,              # transformed_param_length
    )
end

"""
	translate_BUGSGraph_to_BayesianNetwork(g::MetaGraph; init=Dict{Symbol,Any}())

Translates a BUGSGraph (with node metadata stored in NodeInfo) into a BayesianNetwork.
"""
function translate_BUGSGraph_to_BayesianNetwork(
    g::JuliaBUGS.BUGSGraph, evaluation_env, model=nothing
)
    # Retrieve variable labels (stored as VarNames) from g.
    varnames = collect(labels(g))
    n = length(varnames)
    original_graph = g.graph

    # Preallocate arrays/dictionaries.
    names = Vector{VarName}(undef, n)
    names_to_ids = Dict{VarName,Int}()
    loop_vars = Dict{VarName,NamedTuple}()
    distributions = Vector{Function}(undef, n)
    deterministic_fns = Vector{Function}(undef, n)
    stochastic_ids = Int[]
    deterministic_ids = Int[]
    is_stochastic = falses(n)
    is_observed = falses(n)
    node_types = Vector{Symbol}(undef, n)
    transformed_var_lengths = Dict{VarName,Int}()
    transformed_param_length = 0

    if model !== nothing
        if isdefined(model, :transformed_var_lengths)
            transformed_var_lengths = copy(model.transformed_var_lengths)
        end
        if isdefined(model, :transformed_param_length)
            transformed_param_length = model.transformed_param_length
        end
    end

    for (i, varname) in enumerate(varnames)
        nodeinfo = g[varname]
        names[i] = varname
        names_to_ids[varname] = i
        is_stochastic[i] = nodeinfo.is_stochastic
        is_observed[i] = nodeinfo.is_observed
        loop_vars[varname] = nodeinfo.loop_vars

        if nodeinfo.is_stochastic
            distributions[i] = nodeinfo.node_function
            push!(stochastic_ids, i)
            node_types[i] = :stochastic
        else
            deterministic_fns[i] = nodeinfo.node_function
            push!(deterministic_ids, i)
            node_types[i] = :deterministic
        end
    end

    bn = BayesianNetwork(
        SimpleDiGraph{Int}(n),
        names,
        names_to_ids,
        evaluation_env,
        loop_vars,
        distributions,
        deterministic_fns,
        stochastic_ids,
        deterministic_ids,
        is_stochastic,
        is_observed,
        node_types,
        transformed_var_lengths,
        transformed_param_length,
    )

    # Add edges using the BayesianNetwork's mapping.
    for e in edges(original_graph)
        let src_name = bn.names[e.src]
            let dst_name = bn.names[e.dst]
                add_edge!(bn, src_name, dst_name)
            end
        end
    end

    return bn
end

"""
	add_stochastic_vertex!(bn::BayesianNetwork{V,T}, name::V, dist::Any, node_type::Symbol; is_observed::Bool=false) where {V,T}

Add a stochastic vertex with name `name`, a distribution object/function `dist`,
and a declared node_type (`:discrete` or `:continuous`).
"""
function add_stochastic_vertex!(
    bn::BayesianNetwork{V,T},
    name::V,
    dist::Any,
    is_observed::Bool=false,
    node_type::Symbol=:continuous,
)::T where {V,T}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.distributions, dist)
    push!(bn.is_stochastic, true)
    push!(bn.is_observed, is_observed)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.stochastic_ids, id)
    push!(bn.node_types, node_type)
    return id
end

"""
	add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F) where {T,V,F}

Add a deterministic vertex.
"""
function add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F)::T where {T,V,F}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.deterministic_functions, f)
    push!(bn.is_stochastic, false)
    push!(bn.is_observed, false)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.deterministic_ids, id)
    push!(bn.node_types, :deterministic)
    return id
end

"""
	add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V) where {T,V}

Add a directed edge from `from` -> `to`.
"""
function add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V)::Bool where {T,V}
    from_id = bn.names_to_ids[from]
    to_id = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end

function evaluate(bn::BayesianNetwork)
    logp = 0.0
    evaluation_env = bn.evaluation_env

    for (i, varname) in enumerate(bn.names)
        is_stochastic = bn.is_stochastic[i]
        if is_stochastic
            dist_fn = bn.distributions[i](evaluation_env, bn.loop_vars[varname])

            value = AbstractPPL.get(evaluation_env, varname)
            bijector = Bijectors.bijector(dist_fn)
            value_transformed = Bijectors.transform(bijector, value)

            logpdf_val = Distributions.logpdf(dist_fn, value)
            logjac = Bijectors.logabsdetjac(Bijectors.inverse(bijector), value_transformed)
            logp += logpdf_val + logjac

        else
            fn = bn.deterministic_functions[i](evaluation_env, bn.loop_vars[varname])
            evaluation_env = BangBang.setindex!!(evaluation_env, fn, varname)
        end
    end
    return evaluation_env, logp
end

function evaluate_with_values(bn::BayesianNetwork, parameter_values::AbstractVector)
    bugsmodel_node_order = [bn.names[i] for i in topological_sort_by_dfs(bn.graph)]
    var_lengths = bn.transformed_var_lengths

    evaluation_env = deepcopy(bn.evaluation_env)
    current_idx = 1
    logprior, loglikelihood = 0.0, 0.0

    for vn in bugsmodel_node_order
        i = bn.names_to_ids[vn]

        is_stochastic = bn.is_stochastic[i]
        is_observed = bn.is_observed[i]

        if !is_stochastic
            value = bn.deterministic_functions[i](evaluation_env, bn.loop_vars[vn])
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        else
            if !is_observed
                dist = bn.distributions[i](evaluation_env, bn.loop_vars[vn])
                b = Bijectors.bijector(dist)
                # If the variable is not in transformed_var_lengths, calculate it
                if !haskey(var_lengths, vn)
                    var_value = AbstractPPL.get(evaluation_env, vn)
                    transformed_value = Bijectors.transform(b, var_value)
                    var_lengths[vn] = length(transformed_value)
                end
                l = var_lengths[vn]
                b_inv = Bijectors.inverse(b)
                reconstructed_value = JuliaBUGS.reconstruct(
                    b_inv, dist, view(parameter_values, current_idx:(current_idx + l - 1))
                )
                value, logjac = Bijectors.with_logabsdet_jacobian(
                    b_inv, reconstructed_value
                )

                current_idx += l
                logprior += logpdf(dist, value) + logjac
                evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
            else
                dist = bn.distributions[i](evaluation_env, bn.loop_vars[vn])
                loglikelihood += logpdf(dist, AbstractPPL.get(evaluation_env, vn))
            end
        end
    end

    return evaluation_env, logprior + loglikelihood
end

function _precompute_minimal_cache_keys(bn, order::Vector{Int})
    minimal_keys = Dict{Int,Set{Int}}()
    n = length(order)

    for t in 1:n
        current_node_id = order[t]
        future_nodes = t < n ? order[(t + 1):end] : Int[]

        # Collect parents of future nodes + current node's parents
        future_parents = Set{Int}()
        union!(future_parents, inneighbors(bn.graph, current_node_id))
        for n in future_nodes
            union!(future_parents, inneighbors(bn.graph, n))
        end

        # Get visited nodes up to current position
        visited = Set(order[1:t])

        # Store by node ID
        minimal_keys[current_node_id] = intersect(future_parents, visited)
    end

    return minimal_keys
end

function _precompute_minimal_cache_keys(bn)
    return _precompute_minimal_cache_keys(bn, topological_sort_by_dfs(bn.graph))
end

function evaluate_with_marginalization(
    bn::BayesianNetwork{V,T,F},
    parameter_values::AbstractVector;
    caching_strategy::Symbol=:full_env,
    order_heuristic::Symbol=:dfs,  # :dfs, :min_degree, or :min_fill
) where {V,T,F}
    # Get topological ordering of nodes

    sorted_node_ids = topological_sort_by_dfs(bn.graph)

    # Find discrete and continuous variables
    discrete_vars = [
        bn.names[i] for i in sorted_node_ids if
        bn.is_stochastic[i] && !bn.is_observed[i] && bn.node_types[i] == :discrete
    ]

    continuous_vars = [
        bn.names[i] for i in sorted_node_ids if
        bn.is_stochastic[i] && !bn.is_observed[i] && bn.node_types[i] != :discrete
    ]

    # Parameter validation for continuous variables
    total_param_length = 0
    for name in continuous_vars
        if haskey(bn.transformed_var_lengths, name)
            total_param_length += bn.transformed_var_lengths[name]
        end
    end

    if !isempty(continuous_vars) &&
        !isempty(parameter_values) &&
        length(parameter_values) < total_param_length
        error(
            "Parameter vector too short: needed $(total_param_length) elements, but only $(length(parameter_values)) provided.",
        )
    end

    # Initialize environment once
    env = deepcopy(bn.evaluation_env)

    # Size hint for memo dictionary - for optimal performance
    # We expect at most 2^|discrete_vars| * |nodes| entries
    expected_entries = 2^length(discrete_vars) * length(bn.names)
    memo = Dict{Tuple{Int,Int,UInt64},Any}()
    sizehint!(memo, expected_entries)
    if caching_strategy == :minimal_key
        # Precompute minimal keys for memoization
        minimal_keys = _precompute_minimal_cache_keys(bn, sorted_node_ids)
    else
        minimal_keys = nothing
    end

    # Start recursive evaluation with the first node, beginning at parameter index 1
    logp = _marginalize_recursive(
        bn,
        env,
        sorted_node_ids,
        parameter_values,
        1,
        bn.transformed_var_lengths,
        memo,
        caching_strategy,
        minimal_keys,
    )
    return env, logp
end

function _extract_value_for_hash(x)
    # Handle ForwardDiff.Dual
    if hasproperty(x, :value)
        return x.value
        # Handle ReverseDiff.TrackedReal
    elseif isdefined(Main, :ReverseDiff) && x isa Main.ReverseDiff.TrackedReal
        return Main.ReverseDiff.value(x)
    else
        return x
    end
end

"""
	_marginalize_recursive(bn, env, remaining_nodes, parameter_values, param_idx, 
						  var_lengths, memo, caching_strategy, minimal_keys) -> Float64

Recursively compute the log probability of a Bayesian network by marginalizing over discrete variables.

This function processes nodes in topological order, handling:
- Deterministic nodes: Compute values directly
- Observed nodes: Add their log probability
- Discrete unobserved nodes: Marginalize by summing over all possible values
- Continuous unobserved nodes: Use provided parameter values

Supports memoization to avoid redundant computations when the same subproblem is encountered
with the same relevant environment state.
"""
function _marginalize_recursive(
    bn::BayesianNetwork{V,T,F},
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
    memo::Dict{Tuple{Int,Int,UInt64},Any},
    caching_strategy::Symbol,
    minimal_keys,
) where {V,T,F}
    # Base case: no more nodes to process
    if isempty(remaining_nodes)
        return zero(eltype(parameter_values))
    end

    current_id = remaining_nodes[1]
    current_name = bn.names[current_id]

    # Create memo key - be careful with hashing when environment contains AD types
    if caching_strategy == :minimal_key
        relevant_ids = minimal_keys[current_id]
        # Extract only the values for hashing, avoid AD types in hash computation
        relevant_values = Dict(
            bn.names[id] => _extract_value_for_hash(AbstractPPL.get(env, bn.names[id])) for
            id in relevant_ids
        )
        minimal_hash = hash(relevant_values)
        memo_key = (current_id, param_idx, minimal_hash)
    else
        # Hash the environment safely
        env_hash = _safe_hash_env(env)
        memo_key = (current_id, param_idx, env_hash)
    end

    if haskey(memo, memo_key)
        return memo[memo_key]
    end

    is_stochastic = bn.is_stochastic[current_id]
    is_observed = bn.is_observed[current_id]
    is_discrete = bn.node_types[current_id] == :discrete

    if !is_stochastic
        value = bn.deterministic_functions[current_id](env, bn.loop_vars[current_name])
        new_env = BangBang.setindex!!(env, value, current_name)
        result = _marginalize_recursive(
            bn,
            new_env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            caching_strategy,
            minimal_keys,
        )

    elseif is_observed
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        obs_value = AbstractPPL.get(env, current_name)
        obs_logp = logpdf(dist, obs_value)

        # Handle NaN values with proper type
        if isnan(obs_logp)
            obs_logp = -1e20  # Use large negative number instead of -Inf
        end

        remaining_logp = _marginalize_recursive(
            bn,
            env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            caching_strategy,
            minimal_keys,
        )
        result = obs_logp + remaining_logp

    elseif is_discrete
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        possible_values = enumerate_discrete_values(dist)

        logp_branches = Vector{typeof(zero(eltype(parameter_values)))}(
            undef, length(possible_values)
        )

        for (i, value) in enumerate(possible_values)
            branch_env = BangBang.setindex!!(deepcopy(env), value, current_name)

            value_logp = logpdf(dist, value)
            if isnan(value_logp)
                value_logp = -1e20  # Use large negative number instead of -Inf
            end

            remaining_logp = _marginalize_recursive(
                bn,
                branch_env,
                @view(remaining_nodes[2:end]),
                parameter_values,
                param_idx,
                var_lengths,
                memo,
                caching_strategy,
                minimal_keys,
            )

            logp_branches[i] = value_logp + remaining_logp
        end

        result = LogExpFunctions.logsumexp(logp_branches)

    else
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        b = Bijectors.bijector(dist)

        if !haskey(var_lengths, current_name)
            error(
                "Missing transformed length for variable '$(current_name)'. All variables should have their transformed lengths pre-computed in JuliaBUGS.",
            )
        end

        l = var_lengths[current_name]

        if param_idx + l - 1 > length(parameter_values)
            error(
                "Parameter index out of bounds: needed $(param_idx + l - 1) elements, but parameter_values has only $(length(parameter_values)) elements.",
            )
        end

        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, param_idx:(param_idx + l - 1))

        reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)

        new_env = BangBang.setindex!!(env, value, current_name)

        dist_logp = logpdf(dist, value)
        if isnan(dist_logp)
            dist_logp = -1e20 + logjac  # Use large negative number instead of -Inf
        else
            dist_logp += logjac
        end

        next_idx = param_idx + l
        remaining_logp = _marginalize_recursive(
            bn,
            new_env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            next_idx,
            var_lengths,
            memo,
            caching_strategy,
            minimal_keys,
        )

        result = dist_logp + remaining_logp
    end

    memo[memo_key] = result
    return result
end

# Helper function to safely hash environment containing AD types
function _safe_hash_env(env::NamedTuple)
    # Extract just the values for hashing, stripping AD information
    value_dict = Dict(k => _extract_value_for_hash(v) for (k, v) in pairs(env))
    return hash(value_dict)
end

"""
	enumerate_discrete_values(dist)

Return all possible values for a discrete distribution.
Currently supports Categorical, Bernoulli, Binomial, and DiscreteUniform distributions.
"""
function enumerate_discrete_values(dist::DiscreteUnivariateDistribution)
    if dist isa Categorical
        return 1:length(dist.p)
    elseif dist isa Bernoulli
        return [0, 1]
    elseif dist isa Binomial
        # Handle special case where n is 0
        if dist.n == 0
            return 0:0
        else
            return 0:(dist.n)
        end
    elseif dist isa DiscreteUniform
        return (dist.a):(dist.b)
    else
        error(
            "Distribution type $(typeof(dist)) is not currently supported for discrete marginalization",
        )
    end
end

function evaluate_with_marginalization_legacy(
    bn::BayesianNetwork{V,T,F}, parameter_values::AbstractVector
) where {V,T,F}
    # Get topological ordering of nodes
    sorted_node_ids = topological_sort_by_dfs(bn.graph)

    # Find continuous variables (all stochastic unobserved variables that are not discrete)
    continuous_vars = [
        bn.names[i] for i in sorted_node_ids if
        bn.is_stochastic[i] && !bn.is_observed[i] && bn.node_types[i] != :discrete
    ]

    # Calculate total parameter length needed
    total_param_length = 0
    for name in continuous_vars
        if haskey(bn.transformed_var_lengths, name)
            total_param_length += bn.transformed_var_lengths[name]
        end
    end

    # No discrete variables case - use standard evaluation
    discrete_vars = [
        bn.names[i] for i in sorted_node_ids if
        bn.is_stochastic[i] && !bn.is_observed[i] && bn.node_types[i] == :discrete
    ]

    if isempty(discrete_vars)
        return evaluate_with_values(bn, parameter_values)
    end

    # Initialize environment once
    env = deepcopy(bn.evaluation_env)

    # Start recursive evaluation with the first node, beginning at parameter index 1
    logp = _marginalize_recursive_legacy(
        bn, env, sorted_node_ids, parameter_values, 1, bn.transformed_var_lengths
    )

    return env, logp
end

function _marginalize_recursive_legacy(
    bn::BayesianNetwork{V,T,F},
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
) where {V,T,F}
    # Base case: no more nodes to process
    if isempty(remaining_nodes)
        return 0.0
    end

    # Process current node
    current_id = remaining_nodes[1]
    current_name = bn.names[current_id]

    # Check node type
    is_stochastic = bn.is_stochastic[current_id]
    is_observed = bn.is_observed[current_id]
    is_discrete = bn.node_types[current_id] == :discrete

    if !is_stochastic
        # Deterministic node - compute value and continue
        value = bn.deterministic_functions[current_id](env, bn.loop_vars[current_name])
        env = BangBang.setindex!!(env, value, current_name)
        return _marginalize_recursive_legacy(
            bn, env, @view(remaining_nodes[2:end]), parameter_values, param_idx, var_lengths
        )

    elseif is_observed
        # Observed node - add log probability and continue
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        obs_logp = logpdf(dist, AbstractPPL.get(env, current_name))
        remaining_logp = _marginalize_recursive_legacy(
            bn, env, @view(remaining_nodes[2:end]), parameter_values, param_idx, var_lengths
        )
        return obs_logp + remaining_logp

    elseif is_discrete
        # Discrete unobserved node - marginalize over possible values
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        possible_values = enumerate_discrete_values(dist)

        # Collect log probabilities for all possible values
        logp_branches = Vector{Float64}(undef, length(possible_values))

        for (i, value) in enumerate(possible_values)
            # Create a branch-specific environment
            branch_env = BangBang.setindex!!(deepcopy(env), value, current_name)

            # Compute log probability of this value
            value_logp = logpdf(dist, value)

            # Continue evaluation with this assignment
            # Important: We use the same param_idx for all branches since discrete variables
            # don't consume parameters
            remaining_logp = _marginalize_recursive_legacy(
                bn,
                branch_env,
                @view(remaining_nodes[2:end]),
                parameter_values,
                param_idx,
                var_lengths,
            )

            logp_branches[i] = value_logp + remaining_logp
        end

        # Marginalize using logsumexp for numerical stability
        return LogExpFunctions.logsumexp(logp_branches)

    else
        # Continuous unobserved node - use parameter values
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        b = Bijectors.bijector(dist)

        # Ensure variable length is in the dictionary
        if !haskey(var_lengths, current_name)
            error(
                "Missing transformed length for variable '$(current_name)'. All variables should have their transformed lengths pre-computed in JuliaBUGS.",
            )
        end

        l = var_lengths[current_name]

        # Process the continuous variable
        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, param_idx:(param_idx + l - 1))
        reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)

        # Update environment
        env = BangBang.setindex!!(env, value, current_name)

        # Compute log probability and continue with updated parameter index
        dist_logp = logpdf(dist, value) + logjac
        next_idx = param_idx + l
        remaining_logp = _marginalize_recursive_legacy(
            bn, env, @view(remaining_nodes[2:end]), parameter_values, next_idx, var_lengths
        )

        return dist_logp + remaining_logp
    end
end
