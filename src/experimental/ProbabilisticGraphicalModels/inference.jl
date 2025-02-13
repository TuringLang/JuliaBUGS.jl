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
        error(
            "Node $node_id has invalid distribution entry (neither Distribution nor Function).",
        )
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
function sum_discrete_configurations(
    bn::BayesianNetwork, discrete_ids::Vector{Int}, idx::Int
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
            bn.values[bn.names[node_id]] = val
            subval = sum_discrete_configurations(bn, discrete_ids, idx + 1)
            pdf_val = pdf(dist, val)
            println(
                "DEBUG:    subval=$subval, pdf_val=$pdf_val => partial = $(subval * pdf_val)",
            )
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
    function log_posterior(unobserved_values::Dict{Symbol,Float64})
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
                    println(
                        "DEBUG:  Observed $varname=$value => dist=$observed_dist => pdf= $(pdf(observed_dist, value))",
                    )
                    if incompatible
                        println(
                            "DEBUG:    Observed value is incompatible => returning -Inf"
                        )
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
            empty!(bn.values)
            merge!(bn.values, old_values)
        end
    end
    return log_posterior
end
