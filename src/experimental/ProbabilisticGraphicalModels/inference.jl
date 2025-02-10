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

# ###############################################################################
# # 7) Evaluate the model for a set of observations & X1 values
# ###############################################################################
# function evaluate_model(
#     bn::BayesianNetwork, obs::Dict{Symbol,Float64}, X1_values, description::AbstractString
# )
#     println("\n=== $description ===")
#     println("Observations: ", obs)

#     old_values = copy(bn.values)
#     old_observed = copy(bn.is_observed)
#     try
#         for (k, v) in obs
#             id = bn.names_to_ids[k]
#             bn.values[k] = v
#             bn.is_observed[id] = true
#         end

#         log_post = create_log_posterior(bn)
#         results = [(x1, log_post(Dict(:X1 => Float64(x1)))) for x1 in X1_values]

#         max_lp = maximum(last.(results))
#         normalized_post = [(x1, exp(lp - max_lp)) for (x1, lp) in results]

#         for (x1, p) in normalized_post
#             println("  X1 = %.2f => normalized posterior = %.5f\n", x1, p)
#         end
#     finally
#         bn.values = old_values
#         bn.is_observed = old_observed
#     end
# end

# ###############################################################################
# # 8) Simple Network & Test
# ###############################################################################

# function create_test_network()
#     bn = BayesianNetwork{Symbol}()

#     # X1 ~ Bernoulli(0.5)
#     println("DEBUG: Adding X1 => Bernoulli(0.5)")
#     add_stochastic_vertex!(bn, :X1, Bernoulli(0.5), false, :discrete)

#     # X2 ~ Bernoulli(X1)
#     println("DEBUG: Adding X2 => Bernoulli(X1)")
#     println(typeof((x1) -> Bernoulli(x1)))
#     add_stochastic_vertex!(bn, :X2, (x1) -> Bernoulli(x1), false, :discrete)
#     println("DEBUG: Adding edge X1 => X2")
#     add_edge!(bn, :X1, :X2)

#     return bn
# end
# ###############################################################################
# #  More Test Cases for the 2-Node Network
# ###############################################################################

# """
# Test Case 1:
# Compute P(X2 = 0) and verify it matches 0.5.
# Explanation:
#     - X2 = 0 occurs iff X1 = 0 (because X2 ~ Bernoulli(X1)).
#     - X1=0 => prob=0.5, so P(X2=0)=0.5.
# """
# function test_X2_equals_0()
#     println("\n=== Testing P(X2 = 0) ===")

#     # Create the Bayesian Network
#     bn = create_test_network()

#     # Mark X2=0.0 as observed
#     bn.values[:X2] = 0.0
#     bn.is_observed[bn.names_to_ids[:X2]] = true

#     # Possible values of X1
#     X1_values = [0.0, 1.0]

#     # Build the log-posterior function
#     log_post = create_log_posterior(bn)

#     # Compute probabilities for each X1
#     results = [(x1, exp(log_post(Dict(:X1 => x1)))) for x1 in X1_values]

#     # Total probability of X2=0
#     total_prob = sum(last.(results))

#     # Print results
#     println("Results for P(X2 = 0):")
#     for (x1, prob) in results
#         println("  X1 = $x1 => p = $prob")
#     end
#     println("Total P(X2 = 0): $total_prob")

#     # Check if the result matches the expected value (0.5)
#     local expected_value = 0.5
#     @assert isapprox(total_prob, expected_value, atol=1e-6) "Test failed: Expected $expected_value, got $total_prob"
#     println("Test passed!")
# end


# """
# Test Case 2:
# Compute the posterior distribution P(X1 | X2=1).
# We expect:
#     P(X1=1 | X2=1) = 1.0
#     P(X1=0 | X2=1) = 0.0
# Because if X2=1, that means X1 must have been 1.
# """
# function test_X1_given_X2_1()
#     println("\n=== Testing P(X1 | X2 = 1) ===")

#     # Create the Bayesian Network
#     bn = create_test_network()

#     # Mark X2=1.0 as observed
#     bn.values[:X2] = 1.0
#     bn.is_observed[bn.names_to_ids[:X2]] = true

#     # Possible values of X1
#     X1_values = [0.0, 1.0]

#     # Build the log-posterior function
#     log_post = create_log_posterior(bn)

#     # Compute unnormalized posterior for each X1
#     # Then normalize manually to get P(X1 | X2=1).
#     unnormalized = Dict{Float64,Float64}()
#     for x1 in X1_values
#         lp = log_post(Dict(:X1 => x1))
#         unnormalized[x1] = exp(lp)
#     end

#     total = sum(values(unnormalized))
#     posterior = Dict(x1 => unnormalized[x1] / total for x1 in X1_values)

#     # Print results
#     println("Posterior distribution for X1 given X2=1:")
#     for (x1, p) in posterior
#         println("  P(X1=$x1 | X2=1) = $p")
#     end

#     # We expect P(X1=0|X2=1)=0, P(X1=1|X2=1)=1
#     @assert isapprox(posterior[0.0], 0.0, atol=1e-6) "Expected P(X1=0|X2=1) ~ 0.0, got $(posterior[0.0])"
#     @assert isapprox(posterior[1.0], 1.0, atol=1e-6) "Expected P(X1=1|X2=1) ~ 1.0, got $(posterior[1.0])"
#     println("Test passed!")
# end


# """
# Test Case 3:
# Compute the posterior distribution P(X1 | X2=0).
# We expect:
#     P(X1=0 | X2=0) = 1.0
#     P(X1=1 | X2=0) = 0.0
# Because if X2=0, that implies X1=0 for this Bernoulli(X1) setup.
# """
# function test_X1_given_X2_0()
#     println("\n=== Testing P(X1 | X2 = 0) ===")

#     # Create the Bayesian Network
#     bn = create_test_network()

#     # Mark X2=0.0 as observed
#     bn.values[:X2] = 0.0
#     bn.is_observed[bn.names_to_ids[:X2]] = true

#     # Possible values of X1
#     X1_values = [0.0, 1.0]

#     # Build the log-posterior function
#     log_post = create_log_posterior(bn)

#     # Compute unnormalized posterior for each X1
#     unnormalized = Dict{Float64,Float64}()
#     for x1 in X1_values
#         lp = log_post(Dict(:X1 => x1))
#         unnormalized[x1] = exp(lp)
#     end

#     total = sum(values(unnormalized))
#     posterior = Dict(x1 => unnormalized[x1] / total for x1 in X1_values)

#     # Print results
#     println("Posterior distribution for X1 given X2=0:")
#     for (x1, p) in posterior
#         println("  P(X1=$x1 | X2=0) = $p")
#     end

#     # We expect P(X1=0|X2=0)=1, P(X1=1|X2=0)=0
#     @assert isapprox(posterior[0.0], 1.0, atol=1e-6) "Expected P(X1=0|X2=0) ~ 1.0, got $(posterior[0.0])"
#     @assert isapprox(posterior[1.0], 0.0, atol=1e-6) "Expected P(X1=1|X2=0) ~ 0.0, got $(posterior[1.0])"
#     println("Test passed!")
# end
# test_X2_equals_0()
# test_X1_given_X2_1()
# test_X1_given_X2_0()

# logistic(x) = 1 / (1 + exp(-x))

# function create_5node_network_topological()
#     bn = BayesianNetwork{Symbol}()

#     # logistic helper
#     logistic(x) = 1 / (1 + exp(-x))

#     # X1 ~ Normal(0,1) => continuous
#     add_stochastic_vertex!(bn, :X1, Normal(0, 1), :continuous)

#     # X2 ~ Bernoulli(logistic(X1)) => discrete
#     add_stochastic_vertex!(bn, :X2, (x1) -> Bernoulli(logistic(x1)), :discrete)
#     add_edge!(bn, :X1, :X2)

#     # X3 ~ Bernoulli(x2==1 ? 0.7 : 0.3) => discrete
#     add_stochastic_vertex!(bn, :X3, (x2) -> Bernoulli(x2 == 1 ? 0.7 : 0.3), :discrete)
#     add_edge!(bn, :X2, :X3)

#     # X4 ~ Bernoulli(x3==1 ? 0.8 : 0.2) => discrete
#     add_stochastic_vertex!(bn, :X4, (x3) -> Bernoulli(x3 == 1 ? 0.8 : 0.2), :discrete)
#     add_edge!(bn, :X3, :X4)

#     # X5 ~ Normal(x4==1 ? 3.0 : -3.0, 1.0) => continuous
#     add_stochastic_vertex!(bn, :X5, (x4) -> Normal(x4 == 1 ? 3.0 : -3.0, 1.0), :continuous)
#     add_edge!(bn, :X4, :X5)

#     # Topologically sort the nodes and reorder stochastic_ids accordingly
#     sorted_ids = topological_sort(bn.graph)
#     bn.stochastic_ids = [id for id in sorted_ids if id in bn.stochastic_ids]

#     return bn
# end


# function test_topological_order()
#     bn = create_5node_network_topological()
#     # Set observations as before
#     obs = Dict(:X4 => 1.0, :X5 => 2.0)
#     # Mark observations
#     for (k, v) in obs
#         id = bn.names_to_ids[k]
#         bn.values[k] = v
#         bn.is_observed[id] = true
#     end

#     # Attempt to compute logpdf with topological ordering
#     lp = compute_full_logpdf_topo(bn)
#     println("Log probability: ", lp)
# end

# test_topological_order()
