using Graphs
using Distributions
using Printf

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
    node_type::Symbol = :continuous;  # default if not specified
    is_observed::Bool = false
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
    to_id   = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end

###############################################################################
# 3) Create the 5-node chain, marking discrete/continuous explicitly
###############################################################################

logistic(x) = 1 / (1 + exp(-x))

function create_5node_network()
    bn = BayesianNetwork{Symbol}()

    # X1 ~ Normal(0,1) => continuous
    add_stochastic_vertex!(bn, :X1, Normal(0,1), :continuous)

    # X2 ~ Bernoulli(logistic(X1)) => discrete
    add_stochastic_vertex!(bn, :X2, (x1)->Bernoulli(logistic(x1)), :discrete)
    add_edge!(bn, :X1, :X2)

    # X3 ~ Bernoulli(x2==1 ? 0.7 : 0.3) => discrete
    add_stochastic_vertex!(bn, :X3, (x2)->Bernoulli(x2==1 ? 0.7 : 0.3), :discrete)
    add_edge!(bn, :X2, :X3)

    # X4 ~ Bernoulli(x3==1 ? 0.8 : 0.2) => discrete
    add_stochastic_vertex!(bn, :X4, (x3)->Bernoulli(x3==1 ? 0.8 : 0.2), :discrete)
    add_edge!(bn, :X3, :X4)

    # X5 ~ Normal(x4==1 ? 3.0 : -3.0, 1.0) => continuous
    add_stochastic_vertex!(bn, :X5, (x4)->Normal(x4==1 ? 3.0 : -3.0, 1.0), :continuous)
    add_edge!(bn, :X4, :X5)

    return bn
end

###############################################################################
# 4) Parent Helpers: `inneighbors` instead of `predecessors`
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
        pvals = parent_values(bn, node_id)   # calls parent's values
        return stored(pvals...)
    else
        error("Node $node_id has invalid distribution entry (neither Distribution nor Function).")
    end
end

"""
Check if a node is discrete by referencing the stored `node_types`.
We do NOT call get_distribution() here, which avoids the "Missing value for parent" error.
"""
function is_discrete_node(bn::BayesianNetwork, node_id::Int)
    return bn.node_types[node_id] == :discrete
end

###############################################################################
# 5) Summation & Log PDF Calculation
###############################################################################

"""
Compute log-pdf of the current bn.values assignment.
If any parent's value is missing for a node that has a value, we return -Inf.
"""
function compute_full_logpdf(bn::BayesianNetwork)
    logp = 0.0
    for sid in bn.stochastic_ids
        varname = bn.names[sid]
        if haskey(bn.values, varname)
            # ensure parents assigned
            for pid in parent_ids(bn, sid)
                if !haskey(bn.values, bn.names[pid])
                    return -Inf
                end
            end
            dist = get_distribution(bn, sid)
            val  = bn.values[varname]
            lpdf = logpdf(dist, val)
            if isinf(lpdf)
                return -Inf
            end
            logp += lpdf
        end
    end
    return logp
end

"""
Naive enumeration over all unobserved discrete nodes in `discrete_ids`.
Multiply pdf(...) for each assignment, summing up to get total probability.
"""
function sum_discrete_configurations(bn::BayesianNetwork,
                                     discrete_ids::Vector{Int},
                                     idx::Int)
    if idx > length(discrete_ids)
        # base case: all discrete nodes assigned => evaluate logpdf for everything
        return exp( compute_full_logpdf(bn) )
    else
        node_id = discrete_ids[idx]
        dist = get_distribution(bn, node_id)
        total_prob = 0.0
        for val in support(dist)
            bn.values[bn.names[node_id]] = val
            total_prob += sum_discrete_configurations(bn, discrete_ids, idx+1) * pdf(dist, val)
        end
        delete!(bn.values, bn.names[node_id])  # clean up
        return total_prob
    end
end

###############################################################################
# 6) Create a log_posterior function
###############################################################################

function create_log_posterior(bn::BayesianNetwork)
    function log_posterior(unobserved_values::Dict{Symbol,Float64})
        # Save old BN state
        old_values = copy(bn.values)
        try
            # Merge the unobserved values into bn.values
            for (k,v) in unobserved_values
                bn.values[k] = v
            end

            # Identify unobserved, discrete nodes => must sum out
            unobs_discrete_ids = Int[]
            for sid in bn.stochastic_ids
                if !bn.is_observed[sid]
                    varname = bn.names[sid]
                    # If we haven't assigned a value for varname, it is unobserved
                    if !haskey(bn.values, varname) && is_discrete_node(bn, sid)
                        push!(unobs_discrete_ids, sid)
                    end
                end
            end

            if isempty(unobs_discrete_ids)
                # no discrete marginalization => direct logpdf
                return compute_full_logpdf(bn)
            else
                # sum out the discrete ids
                prob_sum = sum_discrete_configurations(bn, unobs_discrete_ids, 1)
                return log(prob_sum)
            end
        finally
            # restore
            bn.values = old_values
        end
    end
    return log_posterior
end

###############################################################################
# 7) Evaluate the model for a set of observations & X1 values
###############################################################################

function evaluate_model(bn::BayesianNetwork, obs::Dict{Symbol,Float64},
                       X1_values, description::AbstractString)
    println("\n=== $description ===")
    println("Observations: ", obs)

    # Save old BN state
    old_values  = copy(bn.values)
    old_observed = copy(bn.is_observed)
    try
        # Condition on `obs` by storing them + marking is_observed
        for (k, v) in obs
            id = bn.names_to_ids[k]
            bn.values[k] = v
            bn.is_observed[id] = true
        end

        # Build the log posterior function
        log_post = create_log_posterior(bn)

        # Evaluate log posterior for each candidate X1
        results = [(x1, log_post(Dict(:X1 => x1))) for x1 in X1_values]

        # Convert to normalized posterior
        max_lp = maximum(last.(results))
        normalized_post = [(x1, exp(lp - max_lp)) for (x1, lp) in results]

        # Print
        for (x1, p) in normalized_post
            @printf("  X1 = %.2f => normalized posterior = %.5f\n", x1, p)
        end
    finally
        # restore BN state
        bn.values = old_values
        bn.is_observed = old_observed
    end
end

###############################################################################
# 8) Demonstration (Same 5-Node chain + 3 test cases)
###############################################################################

model_5_nodes = create_5node_network()

X1_values = 0.0:0.5:1.5

println("\n=== Running test cases on the 5-node model ===")

evaluate_model(
    model_5_nodes,
    Dict(:X4 => 1.0, :X5 => 2.0), 
    X1_values,
    "5-Node Model (X4=1.0, X5=2.0, marginalizing X2,X3)"
)

evaluate_model(
    model_5_nodes,
    Dict(:X5 => 2.0),
    X1_values,
    "5-Node Model (X5=2.0, marginalizing X2,X3,X4)"
)

evaluate_model(
    model_5_nodes,
    Dict(:X2 => 1.0, :X3 => 1.0, :X4 => 1.0, :X5 => 2.0),
    X1_values,
    "5-Node Model (all observed: X2,X3,X4,X5)"
)

println("\nDone.")
