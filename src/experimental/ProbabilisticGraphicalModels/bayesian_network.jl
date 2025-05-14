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

function _extract_parent_values(bn::BayesianNetwork, node_id::Int, env)
    # Get the parents (incoming neighbors) of this node
    parent_ids = inneighbors(bn.graph, node_id)
    
    # Initialize dictionary allowing both Int and Symbol keys 
    parent_values = Dict{Union{Int,Symbol}, Any}()
    
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
"""
function _marginalize_recursive(
    bn::BayesianNetwork{V,T,F},
    env,
    remaining_nodes,
    parameter_values::AbstractVector,
    param_idx::Int,
    var_lengths,
    memo = Dict{Tuple{Int,Int,UInt64},Float64}(),
    debug_stats = Dict{Symbol,Int}(),
    use_full_env::Bool = false,  # Add this parameter
) where {V,T,F}
    debug_stats[:total_calls] = get(debug_stats, :total_calls, 0) + 1
    
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
        debug_stats[:memo_hits] = get(debug_stats, :memo_hits, 0) + 1
        return memo[memo_key]
    else
        debug_stats[:memo_misses] = get(debug_stats, :memo_misses, 0) + 1
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
            bn, new_env, @view(remaining_nodes[2:end]), parameter_values, param_idx, var_lengths, memo, debug_stats, use_full_env
        )

    elseif is_observed
        # Observed node - add log probability and continue
        dist = bn.distributions[current_id](env, bn.loop_vars[current_name])
        
        # Safe logpdf calculation
        obs_value = AbstractPPL.get(env, current_name)
        obs_logp = try 
            logpdf(dist, obs_value)
        catch e
            if get(debug_stats, :debug_level, 0) > 0
                println("Warning: Error in logpdf for $(current_name): $e")
            end
            -Inf  # Treat as zero probability
        end
        
        # Safety check for NaN values
        if isnan(obs_logp)
            if get(debug_stats, :debug_level, 0) > 0
                println("Warning: NaN logpdf for $(current_name), treating as -Inf")
            end
            obs_logp = -Inf
        end
        
        remaining_logp = _marginalize_recursive(
            bn, env, @view(remaining_nodes[2:end]), parameter_values, param_idx, var_lengths, memo, debug_stats, use_full_env
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

            # Compute log probability of this value (with safety check)
            value_logp = try
                logpdf(dist, value)
            catch e
                if get(debug_stats, :debug_level, 0) > 0
                    println("Warning: Error in logpdf for $(current_name)=$(value): $e")
                end
                -Inf
            end
            
            if isnan(value_logp)
                if get(debug_stats, :debug_level, 0) > 0
                    println("Warning: NaN logpdf for $(current_name)=$(value), treating as -Inf")
                end
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
                debug_stats,
                use_full_env
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
                "Parameter index out of bounds: needed $(param_idx + l - 1) elements, but parameter_values has only $(length(parameter_values)) elements."
            )
        end

        # Process the continuous variable
        b_inv = Bijectors.inverse(b)
        param_slice = view(parameter_values, param_idx:(param_idx + l - 1))
        
        reconstructed_value = try
            JuliaBUGS.reconstruct(b_inv, dist, param_slice)
        catch e
            error("Error reconstructing value for $(current_name): $e")
        end
        
        value, logjac = try
            Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)
        catch e
            error("Error computing Jacobian for $(current_name): $e")
        end

        # Update environment
        new_env = BangBang.setindex!!(env, value, current_name)

        # Compute log probability and continue with updated parameter index
        dist_logp = try
            logpdf_val = logpdf(dist, value)
            if isnan(logpdf_val)
                if get(debug_stats, :debug_level, 0) > 0
                    println("Warning: NaN logpdf for $(current_name)=$(value), treating as -Inf")
                end
                -Inf + logjac  # Treat the probability as zero but keep jacobian
            else
                logpdf_val + logjac
            end
        catch e
            if get(debug_stats, :debug_level, 0) > 0
                println("Warning: Error in logpdf for $(current_name): $e")
            end
            -Inf + logjac  # Treat the probability as zero but keep jacobian
        end
        
        next_idx = param_idx + l
        remaining_logp = _marginalize_recursive(
            bn, new_env, @view(remaining_nodes[2:end]), parameter_values, next_idx, var_lengths, memo, debug_stats, use_full_env
        )

        result = dist_logp + remaining_logp
    end

    # Store result in memo before returning
    memo[memo_key] = result
    return result
end

# Main evaluation function with diagnostics
function evaluate_with_marginalization(
    bn::BayesianNetwork{V,T,F}, parameter_values::AbstractVector;
    debug_level::Int = 0, use_full_env::Bool = false
) where {V,T,F}
    # Initialize debug statistics
    debug_stats = Dict{Symbol,Int}(
        :total_calls => 0,
        :memo_hits => 0,
        :memo_misses => 0,
        :debug_level => debug_level
    )
    
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

    # Print some debug information if requested
    if debug_level > 0
        println("Network has $(length(discrete_vars)) discrete variables and $(length(continuous_vars)) continuous variables")
        println("Discrete variables: $(join(string.(discrete_vars), ", "))")
    end

    # No discrete variables case - use standard evaluation
    if isempty(discrete_vars)
        if debug_level > 0
            println("No discrete variables - using standard evaluation")
        end
        return evaluate_with_values(bn, parameter_values)
    end

    # Parameter validation for continuous variables
    total_param_length = 0
    for name in continuous_vars
        if haskey(bn.transformed_var_lengths, name)
            total_param_length += bn.transformed_var_lengths[name]
        end
    end
    
    if !isempty(continuous_vars) && !isempty(parameter_values) && 
       length(parameter_values) < total_param_length
        error(
            "Parameter vector too short: needed $(total_param_length) elements, but only $(length(parameter_values)) provided."
        )
    end

    # Initialize environment once
    env = deepcopy(bn.evaluation_env)
    
    # Size hint for memo dictionary - for optimal performance
    # We expect at most 2^|discrete_vars| * |nodes| entries
    expected_entries = 2^length(discrete_vars) * length(bn.names)
    memo = Dict{Tuple{Int,Int,UInt64},Float64}()
    sizehint!(memo, expected_entries)
    
    if debug_level > 0
        println("Starting marginalization with estimated memo size: $expected_entries")
    end

    # Start recursive evaluation with the first node, beginning at parameter index 1
    logp = _marginalize_recursive(
        bn, env, sorted_node_ids, parameter_values, 1, bn.transformed_var_lengths, memo, debug_stats, use_full_env
    )
    
    # Print summary statistics
    if debug_level > 0
        hit_rate = debug_stats[:memo_hits] / (debug_stats[:memo_hits] + debug_stats[:memo_misses]) * 100
        println("Marginalization complete:")
        println("  Total recursive calls: $(debug_stats[:total_calls])")
        println("  Memo hits: $(debug_stats[:memo_hits])")
        println("  Memo misses: $(debug_stats[:memo_misses])")
        println("  Memo hit rate: $(round(hit_rate, digits=2))%")
        println("  Final memo size: $(length(memo))")
        
        # Print memo entry counts by node
        if debug_level > 1
            node_counts = Dict{V,Int}()
            for (node_id, _, _) in keys(memo)
                node_name = bn.names[node_id]
                node_counts[node_name] = get(node_counts, node_name, 0) + 1
            end
            println("  Memo entries by node:")
            for (name, count) in sort(collect(node_counts), by=x->x[2], rev=true)
                println("    $name: $count")
            end
        end
    end

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
