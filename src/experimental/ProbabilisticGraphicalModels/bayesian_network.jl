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

"""
This function works in some cases, but not all. I have yet to discover why.
    In some functions, we have to hash the whole environment to get the correct answer.
"""
function _extract_parent_values(bn::BayesianNetwork, node_id::Int, env)
    # Get the parents (incoming neighbors) of this node
    parent_ids = inneighbors(bn.graph, node_id)

    # Initialize dictionary allowing both Int and Symbol keys 
    parent_values = Dict{Union{Int,Symbol},Any}()

    # If no parents, just return the empty dictionary
    if isempty(parent_ids)
        # We still need to potentially add metadata
        # No need for an early return
    end

    # Add parent values to the dictionary
    for pid in parent_ids
        parent_name = bn.names[pid]

        try
            value = AbstractPPL.get(env, parent_name)
            parent_values[pid] = value
        catch e
            if isa(e, KeyError) || isa(e, MethodError)
                parent_values[pid] = :__MISSING__
            else
                rethrow(e)
            end
        end
    end

    # Add observation state to metadata
    if bn.is_stochastic[node_id] && bn.is_observed[node_id]
        parent_values[:__OBSERVED__] = true
    end

    return parent_values
end
"""
Enhanced version of marginalize_recursive that uses a more efficient memoization approach.
Only parent values that directly influence a node are included in the memoization key,
which allows for better reuse of computations.

Currently, this function contains two kind of approaches to memoization:
1. **Parent-based memoization**: 
This is the default approach, where only the parent values of the current node are used to create the memo key. 
This is efficient for most cases and allows for better reuse of computations.
The memo_key is (current_id, param_idx, parent_hash).

2. **Full environment memoization**: 
This approach hashes the entire environment to create the memo key. 
It is more accurate but less efficient, as it may lead to a larger number of unique keys. 
This is useful for debugging or when the parent-based approach does not yield correct results.
The memo_key is (current_id, param_idx, env_hash)

Full environment memoization has a substantial speedup, but still not the best, 
as we can save on memory, by hashing only the parent values. I am guessing some of the grandparents value also matters 

For example, 
Chain networks (n=8): Only 17 memo entries vs potentially 256 states
Tree networks (depth=3): Only 14 memo entries vs potentially 128 states
Grid networks (3×3): Only 17 memo entries vs potentially 512 states
"""
function _marginalize_recursive(
    bn::BayesianNetwork{V,T,F},
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
    memo=Dict{Tuple{Int,Int,UInt64},Float64}(),
    use_full_env::Bool=false,  # Keep this parameter
) where {V,T,F}
    # Base case: no more nodes to process
    if isempty(remaining_nodes)
        return 0.0
    end

    # Process current node
    current_id = remaining_nodes[1]
    current_name = bn.names[current_id]

    # Create memo key based on use_full_env flag
    if use_full_env
        # Hash the entire environment for complete correctness
        env_hash = hash(env)
        memo_key = (current_id, param_idx, env_hash)
    else
        # Use the optimized parent-based approach
        parent_values = _extract_parent_values(bn, current_id, env)
        parent_hash = hash(parent_values)
        memo_key = (current_id, param_idx, parent_hash)
    end

    # Check if we've already computed this subproblem
    if haskey(memo, memo_key)
        # Hit! We can reuse a previous calculation
        return memo[memo_key]
    end

    # Check node type
    is_stochastic = bn.is_stochastic[current_id]
    is_observed = bn.is_observed[current_id]
    is_discrete = bn.node_types[current_id] == :discrete

    local result
    if !is_stochastic
        # Deterministic node - compute value and continue
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
            use_full_env,
        )

    elseif is_observed
        # Observed node - add log probability and continue
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])

        # Safe logpdf calculation without try-catch
        obs_value = AbstractPPL.get(env, current_name)
        obs_logp = logpdf(dist, obs_value)
        # Safety check for NaN values
        if isnan(obs_logp)
            obs_logp = -Inf
        end

        remaining_logp = _marginalize_recursive(
            bn,
            env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            use_full_env,
        )
        result = obs_logp + remaining_logp

    elseif is_discrete
        # Discrete unobserved node - marginalize over possible values
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        possible_values = enumerate_discrete_values(dist)

        # Collect log probabilities for all possible values
        logp_branches = Vector{Float64}(undef, length(possible_values))

        for (i, value) in enumerate(possible_values)
            # Create a branch-specific environment
            branch_env = BangBang.setindex!!(deepcopy(env), value, current_name)

            # Compute log probability of this value (without try-catch)
            value_logp = logpdf(dist, value)

            if isnan(value_logp)
                value_logp = -Inf
            end

            # Continue evaluation with this assignment
            remaining_logp = _marginalize_recursive(
                bn,
                branch_env,
                @view(remaining_nodes[2:end]),
                parameter_values,
                param_idx,
                var_lengths,
                memo,
                use_full_env,
            )

            logp_branches[i] = value_logp + remaining_logp
        end

        # Marginalize using logsumexp for numerical stability
        result = LogExpFunctions.logsumexp(logp_branches)

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

        # Check for parameter index out of bounds
        if param_idx + l - 1 > length(parameter_values)
            error(
                "Parameter index out of bounds: needed $(param_idx + l - 1) elements, but parameter_values has only $(length(parameter_values)) elements.",
            )
        end

        # Process the continuous variable
        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, param_idx:(param_idx + l - 1))

        # Removed try-catch blocks
        reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)

        # Update environment
        new_env = BangBang.setindex!!(env, value, current_name)

        # Compute log probability without try-catch
        dist_logp = logpdf(dist, value)
        if isnan(dist_logp)
            dist_logp = -Inf + logjac  # Treat the probability as zero but keep jacobian
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
            use_full_env,
        )

        result = dist_logp + remaining_logp
    end

    # Store result in memo before returning
    memo[memo_key] = result
    return result
end

# Main evaluation function without diagnostics
function evaluate_with_marginalization(
    bn::BayesianNetwork{V,T,F}, parameter_values::AbstractVector; use_full_env::Bool=false
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

    # No discrete variables case - use standard evaluation
    if isempty(discrete_vars)
        return evaluate_with_values(bn, parameter_values)
    end

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
    memo = Dict{Tuple{Int,Int,UInt64},Float64}()
    sizehint!(memo, expected_entries)

    # Start recursive evaluation with the first node, beginning at parameter index 1
    logp = _marginalize_recursive(
        bn,
        env,
        sorted_node_ids,
        parameter_values,
        1,
        bn.transformed_var_lengths,
        memo,
        use_full_env,
    )

    return env, logp
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

"""
    ThreadSafeMemo{K,V}
    
Thread-safe memoization for parallel recursive marginalization
"""
struct ThreadSafeMemo{K,V}
    data::Dict{K,V}
    lock::ReentrantLock
    
    ThreadSafeMemo{K,V}() where {K,V} = new(Dict{K,V}(), ReentrantLock())
end

function Base.haskey(memo::ThreadSafeMemo{K,V}, key::K) where {K,V}
    lock(memo.lock) do
        return haskey(memo.data, key)
    end
end

function Base.getindex(memo::ThreadSafeMemo{K,V}, key::K) where {K,V}
    lock(memo.lock) do
        return memo.data[key]
    end
end

function Base.setindex!(memo::ThreadSafeMemo{K,V}, value::V, key::K) where {K,V}
    lock(memo.lock) do
        memo.data[key] = value
        return value
    end
end

function Base.sizehint!(memo::ThreadSafeMemo{K,V}, n::Integer) where {K,V}
    lock(memo.lock) do
        sizehint!(memo.data, n)
    end
end

"""
    parallel_marginalize_discrete(bn, current_id, env, remaining_nodes, parameter_values, param_idx, var_lengths, memo, use_full_env)
    
Parallelizes summation over discrete variable values while maintaining exact inference.
"""
function parallel_marginalize_discrete(
    bn::BayesianNetwork{V,T,F},
    current_id::Int,
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
    memo,
    use_full_env::Bool
) where {V,T,F}
    current_name = bn.names[current_id]
    dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
    possible_values = enumerate_discrete_values(dist)
    n_values = length(possible_values)
    
    # Pre-allocate result array
    results = Vector{Float64}(undef, n_values)
    
    # Parallel processing of all possible values
    Threads.@threads for i in 1:n_values
        value = possible_values[i]
        
        # Create branch-specific environment (thread-safe deep copy)
        branch_env = BangBang.setindex!!(deepcopy(env), value, current_name)
        
        # Compute log probability of this value
        value_logp = logpdf(dist, value)
        if isnan(value_logp)
            value_logp = -Inf
        end
        
        # Continue evaluation with this assignment
        remaining_logp = _marginalize_recursive_parallel(
            bn,
            branch_env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            use_full_env
        )
        
        results[i] = value_logp + remaining_logp
    end
    
    # Marginalize using logsumexp
    return LogExpFunctions.logsumexp(results)
end

"""
    _marginalize_recursive_parallel(bn, env, remaining_nodes, parameter_values, param_idx, var_lengths, memo, use_full_env)
    
Parallel version of _marginalize_recursive that uses thread-safe memoization and parallel processing for discrete variables.
"""
function _marginalize_recursive_parallel(
    bn::BayesianNetwork{V,T,F},
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
    memo,
    use_full_env::Bool,
    parallel_threshold::Int=4  # Only parallelize when there are enough values
) where {V,T,F}
    # Base case: no more nodes to process
    if isempty(remaining_nodes)
        return 0.0
    end

    # Process current node
    current_id = remaining_nodes[1]
    current_name = bn.names[current_id]

    # Create memo key based on use_full_env flag
    local memo_key
    if use_full_env
        env_hash = hash(env)
        memo_key = (current_id, param_idx, env_hash)
    else
        parent_values = _extract_parent_values(bn, current_id, env)
        parent_hash = hash(parent_values)
        memo_key = (current_id, param_idx, parent_hash)
    end

    # Check memoization (thread-safe if using ThreadSafeMemo)
    if haskey(memo, memo_key)
        return memo[memo_key]
    end

    # Check node type
    is_stochastic = bn.is_stochastic[current_id]
    is_observed = bn.is_observed[current_id]
    is_discrete = bn.node_types[current_id] == :discrete

    local result
    if !is_stochastic
        # Deterministic node - compute value and continue
        value = bn.deterministic_functions[current_id](env, bn.loop_vars[current_name])
        new_env = BangBang.setindex!!(env, value, current_name)
        result = _marginalize_recursive_parallel(
            bn,
            new_env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            use_full_env,
            parallel_threshold
        )

    elseif is_observed
        # Observed node - add log probability and continue
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        obs_value = AbstractPPL.get(env, current_name)
        obs_logp = logpdf(dist, obs_value)
        if isnan(obs_logp)
            obs_logp = -Inf
        end

        remaining_logp = _marginalize_recursive_parallel(
            bn,
            env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            param_idx,
            var_lengths,
            memo,
            use_full_env,
            parallel_threshold
        )
        result = obs_logp + remaining_logp

    elseif is_discrete
        # Discrete unobserved node - marginalize over possible values
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        possible_values = enumerate_discrete_values(dist)
        
        # Use parallel evaluation if there are enough values
        if Threads.nthreads() > 1 && length(possible_values) >= parallel_threshold
            result = parallel_marginalize_discrete(
                bn, current_id, env, remaining_nodes,
                parameter_values, param_idx, var_lengths, memo, use_full_env
            )
        else
            # Sequential evaluation (original code)
            logp_branches = Vector{Float64}(undef, length(possible_values))
            for (i, value) in enumerate(possible_values)
                branch_env = BangBang.setindex!!(deepcopy(env), value, current_name)
                value_logp = logpdf(dist, value)
                if isnan(value_logp)
                    value_logp = -Inf
                end
                
                remaining_logp = _marginalize_recursive_parallel(
                    bn,
                    branch_env,
                    @view(remaining_nodes[2:end]),
                    parameter_values,
                    param_idx,
                    var_lengths,
                    memo,
                    use_full_env,
                    parallel_threshold
                )
                
                logp_branches[i] = value_logp + remaining_logp
            end
            
            result = LogExpFunctions.logsumexp(logp_branches)
        end

    else
        # Continuous unobserved node - use parameter values (same as original)
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        b = Bijectors.bijector(dist)
        
        if !haskey(var_lengths, current_name)
            error("Missing transformed length for variable '$(current_name)'.")
        end
        
        l = var_lengths[current_name]
        
        if param_idx + l - 1 > length(parameter_values)
            error("Parameter index out of bounds: needed $(param_idx + l - 1) elements.")
        end
        
        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, param_idx:(param_idx + l - 1))
        reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, param_slice)
        value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)
        
        new_env = BangBang.setindex!!(env, value, current_name)
        
        dist_logp = logpdf(dist, value)
        if isnan(dist_logp)
            dist_logp = -Inf + logjac
        else
            dist_logp += logjac
        end
        
        next_idx = param_idx + l
        remaining_logp = _marginalize_recursive_parallel(
            bn,
            new_env,
            @view(remaining_nodes[2:end]),
            parameter_values,
            next_idx,
            var_lengths,
            memo,
            use_full_env,
            parallel_threshold
        )
        
        result = dist_logp + remaining_logp
    end

    # Store result in memo (thread-safe operation if using ThreadSafeMemo)
    memo[memo_key] = result
    return result
end

"""
    moralize(g::SimpleDiGraph)
    
Convert a directed graph to its moral graph (undirected with edges between parents).
"""
function moralize(g::SimpleDiGraph)
    n = nv(g)
    moral = SimpleGraph(n)
    
    # Add all edges as undirected
    for e in edges(g)
        # Use fully-qualified name
        Graphs.add_edge!(moral, e.src, e.dst)
    end
    
    # Add edges between parents
    for v in vertices(g)
        parents = inneighbors(g, v)
        for i in 1:length(parents)
            for j in (i+1):length(parents)
                Graphs.add_edge!(moral, parents[i], parents[j])
            end
        end
    end
    
    return moral
end
"""
    extract_subnetwork(bn::BayesianNetwork, node_ids::Vector{Int})
    
Extract a subset of the Bayesian network containing only the specified nodes.
"""
function extract_subnetwork(bn::BayesianNetwork{V,T,F}, node_ids::Vector{Int}) where {V,T,F}
    # Create subgraph
    subgraph = SimpleDiGraph{T}(length(node_ids))
    
    # Create mapping from original to new IDs
    orig_to_new = Dict{T,T}()
    for (new_id, orig_id) in enumerate(node_ids)
        orig_to_new[orig_id] = new_id
    end
    
    # Create new lists for the subnetwork
    names = [bn.names[i] for i in node_ids]
    names_to_ids = Dict{V,T}()
    for (i, name) in enumerate(names)
        names_to_ids[name] = i
    end
    
    stochastic_ids = T[]
    deterministic_ids = T[]
    is_stochastic = falses(length(node_ids))
    is_observed = falses(length(node_ids))
    node_types = Vector{Symbol}(undef, length(node_ids))
    distributions = Vector{F}(undef, length(node_ids))
    deterministic_functions = Vector{F}(undef, length(node_ids))
    
    # Copy node properties
    for (new_id, orig_id) in enumerate(node_ids)
        if bn.is_stochastic[orig_id]
            push!(stochastic_ids, new_id)
            distributions[new_id] = bn.distributions[orig_id]
        else
            push!(deterministic_ids, new_id)
            deterministic_functions[new_id] = bn.deterministic_functions[orig_id]
        end
        
        is_stochastic[new_id] = bn.is_stochastic[orig_id]
        is_observed[new_id] = bn.is_observed[orig_id]
        node_types[new_id] = bn.node_types[orig_id]
    end
    
    # Copy edges within the subgraph
    for orig_id in node_ids
        for dest_id in outneighbors(bn.graph, orig_id)
            if dest_id in node_ids
                Graphs.add_edge!(subgraph, orig_to_new[orig_id], orig_to_new[dest_id])
            end
        end
    end
    
    # Create subset of transformed_var_lengths
    transformed_var_lengths = Dict{V,Int}()
    for name in names
        if haskey(bn.transformed_var_lengths, name)
            transformed_var_lengths[name] = bn.transformed_var_lengths[name]
        end
    end
    
    # Create subset of loop_vars
    loop_vars = Dict{V,NamedTuple}()
    for name in names
        if haskey(bn.loop_vars, name)
            loop_vars[name] = bn.loop_vars[name]
        end
    end
    
    # Create subnetwork
    return BayesianNetwork(
        subgraph,
        names,
        names_to_ids,
        bn.evaluation_env,  # Keep the full environment
        loop_vars,
        distributions,
        deterministic_functions,
        stochastic_ids,
        deterministic_ids,
        is_stochastic,
        is_observed,
        node_types,
        transformed_var_lengths,
        bn.transformed_param_length
    )
end

"""
    parallel_evaluate_components(bn::BayesianNetwork, parameter_values::AbstractVector)
    
Decompose the network into components and evaluate them in parallel.
"""
function parallel_evaluate_components(bn::BayesianNetwork, parameter_values::AbstractVector)
    # Create moral graph for finding independent components
    moral_graph = moralize(bn.graph)
    components = connected_components(moral_graph)
    
    # Single component case - use standard evaluation
    if length(components) <= 1
        return evaluate_with_parallel_marginalization(bn, parameter_values)
    end
    
    # Process components in parallel
    component_results = Vector{Tuple}(undef, length(components))
    
    Threads.@threads for i in 1:length(components)
        component = components[i]
        # Extract subnetwork for this component
        sub_bn = extract_subnetwork(bn, component)
        
        # Get parameter indices for this component
        sub_vars = [sub_bn.names[j] for j in sub_bn.stochastic_ids 
                   if !sub_bn.is_observed[j] && sub_bn.node_types[j] != :discrete]
        
        # Extract parameters for continuous variables in this component
        sub_params = Float64[]
        if !isempty(sub_vars)
            param_idx = 1
            for name in bn.names
                if name in sub_vars && haskey(bn.transformed_var_lengths, name)
                    l = bn.transformed_var_lengths[name]
                    if param_idx + l - 1 <= length(parameter_values)
                        append!(sub_params, parameter_values[param_idx:(param_idx + l - 1)])
                    end
                    param_idx += l
                end
            end
        end
        
        # Evaluate component
        sub_env, sub_logp = evaluate_with_parallel_marginalization(sub_bn, sub_params)
        component_results[i] = (sub_env, sub_logp)
    end
    
    # Combine results - WITHOUT MODIFYING bn
    total_env = deepcopy(bn.evaluation_env)
    total_logp = 0.0
    
    for (sub_env, sub_logp) in component_results
        # Update variables in the environment
        for name in keys(sub_env)
            if name in propertynames(total_env)
                total_env = BangBang.setindex!!(total_env, sub_env[name], name)
            end
        end
        total_logp += sub_logp
    end
    
    return total_env, total_logp
end

"""
    evaluate_with_parallel_marginalization(
        bn::BayesianNetwork, 
        parameter_values::AbstractVector;
        use_full_env::Bool=false,
        parallel_threshold::Int=4,
        thread_safe_memo::Bool=true
    )
    
Evaluate the Bayesian network with parallel computation strategies while maintaining exact inference.
"""
function evaluate_with_parallel_marginalization(
    bn::BayesianNetwork{V,T,F},
    parameter_values::AbstractVector;
    use_full_env::Bool=false,
    parallel_threshold::Int=4,
    thread_safe_memo::Bool=true
) where {V,T,F}
    # Get topological ordering of nodes
    sorted_node_ids = topological_sort_by_dfs(bn.graph)

    # Find discrete variables (same as in original function)
    discrete_vars = [
        bn.names[i] for i in sorted_node_ids if
        bn.is_stochastic[i] && !bn.is_observed[i] && bn.node_types[i] == :discrete
    ]

    # No discrete variables case - use standard evaluation
    if isempty(discrete_vars)
        return evaluate_with_values(bn, parameter_values)
    end

    # Initialize environment
    env = deepcopy(bn.evaluation_env)

    # Create appropriate memo type based on threading needs
    if thread_safe_memo && Threads.nthreads() > 1
        # Thread-safe memo for parallel execution
        expected_entries = 2^length(discrete_vars) * length(bn.names)
        memo = ThreadSafeMemo{Tuple{Int,Int,UInt64},Float64}()
        sizehint!(memo, expected_entries)
    else
        # Standard dictionary for sequential execution
        expected_entries = 2^length(discrete_vars) * length(bn.names)
        memo = Dict{Tuple{Int,Int,UInt64},Float64}()
        sizehint!(memo, expected_entries)
    end

    # Start recursive evaluation with parallel processing
    logp = _marginalize_recursive_parallel(
        bn,
        env,
        sorted_node_ids,
        parameter_values,
        1,
        bn.transformed_var_lengths,
        memo,
        use_full_env,
        parallel_threshold
    )

    return env, logp
end

"""
    batch_evaluate(bn::BayesianNetwork, parameter_sets::Vector{<:AbstractVector})
    
Evaluates the model with multiple parameter sets in parallel.
"""
function batch_evaluate(
    bn::BayesianNetwork, 
    parameter_sets::Vector{<:AbstractVector}
)
    n_sets = length(parameter_sets)
    results = Vector{Tuple}(undef, n_sets)
    
    Threads.@threads for i in 1:n_sets
        results[i] = evaluate_with_optimal_parallelism(bn, parameter_sets[i])
    end
    
    return results
end

"""
    evaluate_with_optimal_parallelism(
        bn::BayesianNetwork, 
        parameter_values::AbstractVector;
        decompose::Bool=true,
        use_full_env::Bool=false
    )
    
Automatically choose the best parallelization strategy based on network characteristics.
"""
function evaluate_with_optimal_parallelism(
    bn::BayesianNetwork,
    parameter_values::AbstractVector;
    decompose::Bool=true,
    use_full_env::Bool=false
)
    # Check for graph decomposition first if enabled
    if decompose
        # Try decomposing the graph into independent components
        moral_graph = moralize(bn.graph)
        components = connected_components(moral_graph)
        
        if length(components) > 1
            # Network is decomposable - use component-based parallelism
            return parallel_evaluate_components(bn, parameter_values)
        end
    end
    
    # Network is not decomposable or decomposition is disabled
    # Use parallel marginalization instead
    return evaluate_with_parallel_marginalization(
        bn, 
        parameter_values; 
        use_full_env=use_full_env
    )
end