using Graphs
using Distributions
using Printf
using BenchmarkTools

###############################################################################
# 1) Make a mutable struct and store :discrete or :continuous at creation time
###############################################################################

mutable struct BayesianNetwork{V,T,F}
    graph::SimpleDiGraph{T}
    names::Vector{V}
    names_to_ids::Dict{V,T}
    values::Dict{V,Any}
    distributions::Vector{Any}            # Distribution or function returning a Distribution
    deterministic_functions::Vector{F}    # (unused here)
    stochastic_ids::Vector{T}
    deterministic_ids::Vector{T}
    is_stochastic::BitVector
    is_observed::BitVector
    node_types::Vector{Symbol}            # e.g. :discrete or :continuous
end

"""
Create an empty BayesianNetwork with Symbol variable names and Int node IDs.
"""
function BayesianNetwork{V}() where {V}
    return BayesianNetwork(
        SimpleDiGraph{Int}(),
        V[],
        Dict{V,Int}(),
        Dict{V,Any}(),
        Any[],
        Any[],
        Int[],
        Int[],
        BitVector(),
        BitVector(),
        Symbol[],   # store node_types in parallel
    )
end

###############################################################################
# 2) Add Node & Edge Helpers
###############################################################################

"""
Add a stochastic vertex with name `name`, a distribution object/function `dist`,
and a declared node_type (`:discrete` or `:continuous`).
"""
function add_stochastic_vertex!(
    bn::BayesianNetwork{V,T},
    name::V,
    dist::Any,
    node_type::Symbol=:continuous;  # default if not specified
    is_observed::Bool=false,
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
Add a deterministic vertex (unused here, but for completeness).
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
Add a directed edge from `from` -> `to`.
"""
function add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V)::Bool where {T,V}
    from_id = bn.names_to_ids[from]
    to_id = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end

###############################################################################
# 4) Parent Helpers
###############################################################################

function parent_ids(bn::BayesianNetwork, node_id::Int)
    # For a node_id, get all incoming edges.
    return inneighbors(bn.graph, node_id)
end

function parent_values(bn::BayesianNetwork, node_id::Int)
    # Retrieve the (already assigned) parent values in ascending ID order.
    pids = parent_ids(bn, node_id)
    sort!(pids)
    vals = Any[]
    for pid in pids
        varname = bn.names[pid]
        if !haskey(bn.values, varname)
            error("Missing value for parent $varname of node id=$node_id")
        end
        push!(vals, bn.values[varname])
    end
    return vals
end

"""
Returns the Distribution object for a node, calling its stored function if needed.
"""
function get_distribution(bn::BayesianNetwork, node_id::Int)::Distribution
    stored = bn.distributions[node_id]
    if stored isa Distribution
        return stored
    elseif stored isa Function
        pvals = parent_values(bn, node_id)
        return stored(pvals...)
    else
        error("Node $node_id has invalid distribution entry (neither Distribution nor Function).")
    end
end

"""
Check if a node is discrete by referencing the stored `node_types`.
"""
function is_discrete_node(bn::BayesianNetwork, node_id::Int)
    return bn.node_types[node_id] == :discrete
end

###############################################################################
# 5) Summation & Log PDF Calculation
###############################################################################

function compute_full_logpdf(bn::BayesianNetwork)
    println("DEBUG: compute_full_logpdf(bn) called.")
    logp = 0.0
    for sid in bn.stochastic_ids
        varname = bn.names[sid]
        # Only evaluate if this node has a value assigned
        if haskey(bn.values, varname)
            println("DEBUG:  Node = $varname, value = $(bn.values[varname])")
            # Ensure parents are assigned
            for pid in parent_ids(bn, sid)
                pvar = bn.names[pid]
                if !haskey(bn.values, pvar)
                    println("DEBUG:  Missing parent $pvar => returning -Inf")
                    return -Inf
                end
            end
            dist = get_distribution(bn, sid)
            val = bn.values[varname]
            println("DEBUG:  get_distribution($sid) => $dist, node value = $val")
            lpdf = logpdf(dist, val)
            println("DEBUG:  logpdf($dist, $val) => $lpdf")
            if isinf(lpdf)
                println("DEBUG:  logpdf is -Inf => returning -Inf")
                return -Inf
            end
            logp += lpdf
        end
    end
    println("DEBUG: final logp = $logp")
    return logp
end

"""
Naive enumeration over all unobserved discrete nodes in `discrete_ids`.
Multiply pdf(...) for each assignment, summing up to get total probability.
"""
function sum_discrete_configurations(bn::BayesianNetwork, discrete_ids::Vector{Int}, idx::Int)
    println("DEBUG: sum_discrete_configurations idx=$idx, discrete_ids=$discrete_ids")
    if idx > length(discrete_ids)
        local val = exp(compute_full_logpdf(bn))
        println("DEBUG: base case => returning $val")
        return val
    else
        node_id = discrete_ids[idx]
        dist = get_distribution(bn, node_id)
        println("DEBUG:  Summation for node_id=$node_id => distribution=$dist")
        total_prob = 0.0
        for val in support(dist)
            println("DEBUG:    Trying val=$val for node $(bn.names[node_id])")
            bn.values[bn.names[node_id]] = val
            subval = sum_discrete_configurations(bn, discrete_ids, idx + 1)
            pdf_val = pdf(dist, val)
            println("DEBUG:    subval=$subval, pdf_val=$pdf_val => partial = $(subval * pdf_val)")
            total_prob += subval * pdf_val
        end
        delete!(bn.values, bn.names[node_id])
        println("DEBUG: sum_discrete_configurations => total_prob=$total_prob")
        return total_prob
    end
end

###############################################################################
# 6) Create a log_posterior function
###############################################################################

function create_log_posterior(bn::BayesianNetwork)
    println("DEBUG: create_log_posterior called for BN with $(nv(bn.graph)) nodes.")
    function log_posterior(unobserved_values::Dict{Symbol, Float64})
        println("DEBUG:  log_posterior called with unobserved_values=$unobserved_values")
        old_values = copy(bn.values)
        try
            # Merge the unobserved values into bn.values
            for (k, v) in unobserved_values
                bn.values[k] = v
                println("DEBUG:    Setting bn.values[$k] = $v")
            end

            # Identify unobserved, discrete nodes => must sum out
            unobs_discrete_ids = Int[]
            for sid in bn.stochastic_ids
                if !bn.is_observed[sid]
                    varname = bn.names[sid]
                    if !haskey(bn.values, varname) && is_discrete_node(bn, sid)
                        push!(unobs_discrete_ids, sid)
                    end
                end
            end
            println("DEBUG:  unobs_discrete_ids = $unobs_discrete_ids")

            # Optionally check for observed but incompatible values
            for (varname, value) in bn.values
                node_id = bn.names_to_ids[varname]
                if bn.is_observed[node_id]
                    observed_dist = get_distribution(bn, node_id)
                    incompatible = (pdf(observed_dist, value) == 0.0)
                    println("DEBUG:  Observed $varname=$value => dist=$observed_dist => pdf= $(pdf(observed_dist, value))")
                    if incompatible
                        println("DEBUG:    Observed value is incompatible => returning -Inf")
                        return -Inf
                    end
                end
            end

            if isempty(unobs_discrete_ids)
                println("DEBUG:  No discrete marginalization => direct logpdf")
                lp = compute_full_logpdf(bn)
                println("DEBUG:  compute_full_logpdf => $lp")
                return lp
            else
                println("DEBUG:  Summing out discrete IDs => $unobs_discrete_ids")
                prob_sum = sum_discrete_configurations(bn, unobs_discrete_ids, 1)
                println("DEBUG:  sum_discrete_configurations => $prob_sum")
                return log(prob_sum)
            end
        finally
            bn.values = old_values
        end
    end
    return log_posterior
end

function compute_full_logpdf_topo(bn::BayesianNetwork)
    println("DEBUG: compute_full_logpdf_topo called.")
    logp = 0.0
    # Iterate nodes in topological order
    for sid in bn.stochastic_ids
        varname = bn.names[sid]
        if haskey(bn.values, varname)
            # Check if all parents are assigned
            all_parents_assigned = true
            for pid in parent_ids(bn, sid)
                pvar = bn.names[pid]
                if !haskey(bn.values, pvar)
                    all_parents_assigned = false
                    break
                end
            end
            if !all_parents_assigned
                println("DEBUG: Skipping node $varname due to missing parents.")
                continue
            end
            # If all parents assigned, compute logpdf
            dist = get_distribution(bn, sid)
            val = bn.values[varname]
            lpdf = logpdf(dist, val)
            if isinf(lpdf)
                return -Inf
            end
            logp += lpdf
        end
    end
    println("DEBUG: final logp = $logp")
    return logp
end

###############################################################################
# 7) Evaluate the model for a set of observations & X1 values
###############################################################################
function evaluate_model(
    bn::BayesianNetwork, obs::Dict{Symbol,Float64}, X1_values, description::AbstractString
)
    println("\n=== $description ===")
    println("Observations: ", obs)

    old_values = copy(bn.values)
    old_observed = copy(bn.is_observed)
    try
        for (k, v) in obs
            id = bn.names_to_ids[k]
            bn.values[k] = v
            bn.is_observed[id] = true
        end

        log_post = create_log_posterior(bn)
        results = [(x1, log_post(Dict(:X1 => Float64(x1)))) for x1 in X1_values]

        max_lp = maximum(last.(results))
        normalized_post = [(x1, exp(lp - max_lp)) for (x1, lp) in results]

        for (x1, p) in normalized_post
            @printf("  X1 = %.2f => normalized posterior = %.5f\n", x1, p)
        end
    finally
        bn.values = old_values
        bn.is_observed = old_observed
    end
end

function sum_discrete_configurations_with_cache(
    bn::BayesianNetwork,
    discrete_ids::Vector{Int},
    idx::Int,
    cache::Dict{Tuple{Int, Int}, Float64}
)
    println("DEBUG: sum_discrete_configurations idx=$idx, discrete_ids=$discrete_ids")
    
    if idx > length(discrete_ids)
        local val = exp(compute_full_logpdf(bn))
        println("DEBUG: base case => returning $val")
        return val
    else
        node_id = discrete_ids[idx]
        dist = get_distribution(bn, node_id)
        println("DEBUG:  Summation for node_id=$node_id => distribution=$dist")
        total_prob = 0.0

        for val in support(dist)
            println("DEBUG:    Trying val=$val for node $(bn.names[node_id])")

            # Check the cache
            cache_key = (node_id, val)
            if haskey(cache, cache_key)
                println("DEBUG:    Cache hit for $cache_key => $(cache[cache_key])")
                total_prob += cache[cache_key]
                continue
            end

            # Compute recursively if not cached
            bn.values[bn.names[node_id]] = val
            subval = sum_discrete_configurations_with_cache(bn, discrete_ids, idx + 1, cache)
            pdf_val = pdf(dist, val)
            println("DEBUG:    subval=$subval, pdf_val=$pdf_val => partial = $(subval * pdf_val)")

            result = subval * pdf_val
            cache[cache_key] = result  # Store in cache
            total_prob += result
        end

        delete!(bn.values, bn.names[node_id])
        println("DEBUG: sum_discrete_configurations => total_prob=$total_prob")
        return total_prob
    end
end


function create_log_posterior_with_cache(bn::BayesianNetwork)
    println("DEBUG: create_log_posterior_with_cache called for BN with $(nv(bn.graph)) nodes.")
    function log_posterior(unobserved_values::Dict{Symbol, Float64})
        println("DEBUG:  log_posterior called with unobserved_values=$unobserved_values")
        old_values = copy(bn.values)
        try
            # Merge the unobserved values into bn.values
            for (k, v) in unobserved_values
                bn.values[k] = v
                println("DEBUG:    Setting bn.values[$k] = $v")
            end

            # Identify unobserved, discrete nodes => must sum out
            unobs_discrete_ids = Int[]
            for sid in bn.stochastic_ids
                if !bn.is_observed[sid]
                    varname = bn.names[sid]
                    if !haskey(bn.values, varname) && is_discrete_node(bn, sid)
                        push!(unobs_discrete_ids, sid)
                    end
                end
            end
            println("DEBUG:  unobs_discrete_ids = $unobs_discrete_ids")

            if isempty(unobs_discrete_ids)
                println("DEBUG:  No discrete marginalization => direct logpdf")
                lp = compute_full_logpdf(bn)
                println("DEBUG:  compute_full_logpdf => $lp")
                return lp
            else
                println("DEBUG:  Summing out discrete IDs with cache => $unobs_discrete_ids")
                cache = Dict{Tuple{Int, Int}, Float64}()  # Initialize cache
                prob_sum = sum_discrete_configurations_with_cache(bn, unobs_discrete_ids, 1, cache)
                println("DEBUG:  sum_discrete_configurations_with_cache => $prob_sum")
                return log(prob_sum)
            end
        finally
            bn.values = old_values
        end
    end
    return log_posterior
end


function create_hmm_network()
    bn = BayesianNetwork{Symbol}()

    # Add hidden states X1, X2, X3
    add_stochastic_vertex!(bn, :X1, Bernoulli(0.5), :discrete)  # Prior on X1
    add_stochastic_vertex!(bn, :X2, (x1) -> Bernoulli(x1 == 1 ? 0.7 : 0.4), :discrete)
    add_stochastic_vertex!(bn, :X3, (x2) -> Bernoulli(x2 == 1 ? 0.7 : 0.4), :discrete)

    # Add edges for state transitions
    add_edge!(bn, :X1, :X2)
    add_edge!(bn, :X2, :X3)

    # Add observations O1, O2, O3
    add_stochastic_vertex!(bn, :O1, (x1) -> Bernoulli(x1 == 1 ? 0.9 : 0.2), :discrete)
    add_stochastic_vertex!(bn, :O2, (x2) -> Bernoulli(x2 == 1 ? 0.9 : 0.2), :discrete)
    add_stochastic_vertex!(bn, :O3, (x3) -> Bernoulli(x3 == 1 ? 0.9 : 0.2), :discrete)

    # Add edges for emissions
    add_edge!(bn, :X1, :O1)
    add_edge!(bn, :X2, :O2)
    add_edge!(bn, :X3, :O3)

    return bn
end

function create_long_hmm_chain(num_states::Int)
    bn = BayesianNetwork{Symbol}()

    # Add the first hidden state
    add_stochastic_vertex!(bn, Symbol("X1"), Bernoulli(0.5), :discrete)

    # Add the rest of the chain
    for t in 2:num_states
        add_stochastic_vertex!(
            bn,
            Symbol("X$t"),  # Use string concatenation
            (x_prev) -> Bernoulli(x_prev == 1 ? 0.7 : 0.4),
            :discrete
        )
        add_edge!(bn, Symbol("X$(t-1)"), Symbol("X$t"))  # String concatenation
    end

    # Add observations
    for t in 1:num_states
        add_stochastic_vertex!(
            bn,
            Symbol("O$t"),  # Use string concatenation
            (x) -> Bernoulli(x == 1 ? 0.9 : 0.2),
            :discrete
        )
        add_edge!(bn, Symbol("X$t"), Symbol("O$t"))  # String concatenation
    end

    return bn
end

function generate_observations(bn::BayesianNetwork, num_states::Int)
    obs = Dict{Symbol, Float64}()
    for t in 1:num_states
        obs[Symbol("O$t")] = rand() < 0.5 ? 1.0 : 0.0  # Correct string concatenation
    end
    return obs
end

function performance_comparison_long_chain(num_states::Int)
    println("=== Testing HMM with $num_states States ===")

    # Create the HMM network
    bn = create_long_hmm_chain(num_states)

    # Generate observations
    obs = generate_observations(bn, num_states)
    println("Generated Observations: ", obs)

    # Set observations in the Bayesian network
    for (k, v) in obs
        id = bn.names_to_ids[k]
        bn.values[k] = v
        bn.is_observed[id] = true
    end

    # Identify unobserved discrete nodes (hidden states)
    unobs_discrete_ids = Int[]
    for sid in bn.stochastic_ids
        if !bn.is_observed[sid] && is_discrete_node(bn, sid)
            push!(unobs_discrete_ids, sid)
        end
    end

    # Performance test: Without DP
    println("\n=== Performance without DP ===")
    @time likelihood_no_dp = sum_discrete_configurations(bn, unobs_discrete_ids, 1)

    # Performance test: With DP
    println("\n=== Performance with DP ===")
    cache = Dict{Tuple{Int, Int}, Float64}()  # Initialize the cache
    @time likelihood_with_dp = sum_discrete_configurations_with_cache(bn, unobs_discrete_ids, 1, cache)

    # Print results
    println("\nLikelihood (without DP): $likelihood_no_dp")
    println("Likelihood (with DP): $likelihood_with_dp")
end


function test_sum_discrete_configurations_hmm()
    # Create the HMM network
    bn = create_hmm_network()

    # Set observations
    obs = Dict(:O1 => 1.0, :O2 => 0.0, :O3 => 1.0)
    for (k, v) in obs
        id = bn.names_to_ids[k]
        bn.values[k] = v
        bn.is_observed[id] = true
    end

    # Identify unobserved discrete nodes (hidden states)
    unobs_discrete_ids = Int[]
    for sid in bn.stochastic_ids
        if !bn.is_observed[sid] && is_discrete_node(bn, sid)
            push!(unobs_discrete_ids, sid)
        end
    end

    # Call sum_discrete_configurations
    cache = Dict{Tuple{Int, Int}, Float64}()  # Initialize the cache
    likelihood = sum_discrete_configurations_with_cache(bn, unobs_discrete_ids, 1, cache)

    # Print the results
    println("Likelihood of the observation sequence: ", likelihood)
end


function test_create_log_posterior_hmm()
    # Create the HMM network
    bn = create_hmm_network()

    # Set observations
    obs = Dict(:O1 => 1.0, :O2 => 0.0, :O3 => 1.0)
    for (k, v) in obs
        id = bn.names_to_ids[k]
        bn.values[k] = v
        bn.is_observed[id] = true
    end

    # Build the log-posterior function
    log_post = create_log_posterior_with_cache(bn)

    # Compute posterior for some configurations of X1, X2, X3
    unobserved_configs = [
        Dict(:X1 => 0.0, :X2 => 0.0, :X3 => 0.0),
        Dict(:X1 => 1.0, :X2 => 1.0, :X3 => 1.0),
        Dict(:X1 => 1.0, :X2 => 0.0, :X3 => 1.0)
    ]

    for config in unobserved_configs
        lp = log_post(config)
        println("Log posterior for configuration $config: ", lp)
    end
end

test_sum_discrete_configurations_hmm()
test_create_log_posterior_hmm()

using BenchmarkTools

function performance_comparison_hmm()
    # Create the HMM network
    bn = create_hmm_network()

    # Set observations
    obs = Dict(:O1 => 1.0, :O2 => 0.0, :O3 => 1.0)
    for (k, v) in obs
        id = bn.names_to_ids[k]
        bn.values[k] = v
        bn.is_observed[id] = true
    end

    # Identify unobserved discrete nodes (hidden states)
    unobs_discrete_ids = Int[]
    for sid in bn.stochastic_ids
        if !bn.is_observed[sid] && is_discrete_node(bn, sid)
            push!(unobs_discrete_ids, sid)
        end
    end

    # Performance test: Without DP
    println("\n=== Performance without DP ===")
    @time likelihood_no_dp = sum_discrete_configurations(bn, unobs_discrete_ids, 1)

    # Performance test: With DP
    println("\n=== Performance with DP ===")
    cache = Dict{Tuple{Int, Int}, Float64}()  # Initialize the cache
    @time likelihood_with_dp = sum_discrete_configurations_with_cache(bn, unobs_discrete_ids, 1, cache)

    # Print results
    println("\nLikelihood (without DP): $likelihood_no_dp")
    println("Likelihood (with DP): $likelihood_with_dp")
end

# performance_comparison_hmm()
# for num_states in [10]
#     performance_comparison_long_chain(num_states)
# end


using BenchmarkTools
using Plots

# Function to create a long Markov chain HMM
function create_long_hmm_chain(num_states::Int)
    bn = BayesianNetwork{Symbol}()

    # Add the first hidden state
    add_stochastic_vertex!(bn, Symbol("X1"), Bernoulli(0.5), :discrete)

    # Add the rest of the chain
    for t in 2:num_states
        add_stochastic_vertex!(
            bn,
            Symbol("X$t"),
            (x_prev) -> Bernoulli(x_prev == 1 ? 0.7 : 0.4),
            :discrete
        )
        add_edge!(bn, Symbol("X$(t-1)"), Symbol("X$t"))
    end

    # Add observations
    for t in 1:num_states
        add_stochastic_vertex!(
            bn,
            Symbol("O$t"),
            (x) -> Bernoulli(x == 1 ? 0.9 : 0.2),
            :discrete
        )
        add_edge!(bn, Symbol("X$t"), Symbol("O$t"))
    end

    return bn
end

# Function to generate random observations
function generate_observations(bn::BayesianNetwork, num_states::Int)
    obs = Dict{Symbol, Float64}()
    for t in 1:num_states
        obs[Symbol("O$t")] = rand() < 0.5 ? 1.0 : 0.0
    end
    return obs
end

# Performance comparison for a given Markov chain length
function performance_comparison_long_chain(num_states::Int)
    # Create the HMM network
    bn = create_long_hmm_chain(num_states)

    # Generate observations
    obs = generate_observations(bn, num_states)

    # Set observations in the Bayesian network
    for (k, v) in obs
        id = bn.names_to_ids[k]
        bn.values[k] = v
        bn.is_observed[id] = true
    end

    # Identify unobserved discrete nodes (hidden states)
    unobs_discrete_ids = Int[]
    for sid in bn.stochastic_ids
        if !bn.is_observed[sid] && is_discrete_node(bn, sid)
            push!(unobs_discrete_ids, sid)
        end
    end

    # Measure time without DP
    time_no_dp = @elapsed sum_discrete_configurations(bn, unobs_discrete_ids, 1)

    # Measure time with DP
    cache = Dict{Tuple{Int, Int}, Float64}()  # Initialize the cache
    time_with_dp = @elapsed sum_discrete_configurations_with_cache(bn, unobs_discrete_ids, 1, cache)

    return time_no_dp, time_with_dp
end

# Collect data for different Markov chain lengths
chain_lengths = [1, 3, 5, 7, 9, 10]
times_no_dp = Float64[]
times_with_dp = Float64[]

for length in chain_lengths
    time_no_dp, time_with_dp = performance_comparison_long_chain(length)
    push!(times_no_dp, time_no_dp)
    push!(times_with_dp, time_with_dp)
end
plot(
    chain_lengths,
    [times_no_dp times_with_dp],
    labels=["Without DP" "With DP"],
    xlabel="Length of Markov Chain",
    ylabel="Time (seconds)",
    title="Performance Comparison: Time vs Length of Markov Chain",
    legend=:topleft,  # Correct symbol for legend position
    marker=:circle,
    lw=2
)

println(times_no_dp)
println(times_with_dp)