
# function create_3node_network()
#     bn = BayesianNetwork{Symbol}()

#     # X1 ~ Bernoulli(0.5)
#     add_stochastic_vertex!(bn, :X1, Bernoulli(0.5), :discrete)

#     # X2 ~ Bernoulli(X1)
#     add_stochastic_vertex!(bn, :X2, (x1) -> Bernoulli(x1), :discrete)
#     add_edge!(bn, :X1, :X2)

#     # X3 ~ Bernoulli(X2)
#     add_stochastic_vertex!(bn, :X3, (x2) -> Bernoulli(x2), :discrete)
#     add_edge!(bn, :X2, :X3)

#     return bn
# end
# function test_P_X3_equals_1()
#     # Create the 3-node network
#     bn = create_3node_network()

#     # Mark X3 = 1.0 as observed
#     bn.values[:X3] = 1.0
#     bn.is_observed[bn.names_to_ids[:X3]] = true

#     # We'll sum over unobserved discrete nodes X1 and X2.
#     unobs_discrete_ids = Int[]
#     for sid in bn.stochastic_ids
#         if !bn.is_observed[sid] && bn.node_types[sid] == :discrete
#             push!(unobs_discrete_ids, sid)
#         end
#     end

#     # Build log-posterior function
#     log_post = create_log_posterior(bn)

#     # Enumerate over possible values of X1 and X2
#     results = []
#     for x1 in [0.0, 1.0]
#         for x2 in [0.0, 1.0]
#             # Evaluate log-posterior with assignments for X1, X2
#             lp = log_post(Dict(:X1 => x1, :X2 => x2))
#             prob = exp(lp)
#             push!(results, ((x1, x2), prob))
#         end
#     end

#     # Sum over all configurations to get P(X3 = 1)
#     total_prob = sum(prob for ((_, _), prob) in results)

#     println("Results for P(X3 = 1):")
#     for ((x1, x2), prob) in results
#         println("  X1 = $x1, X2 = $x2 => contribution = $prob")
#     end
#     println("Total P(X3 = 1): $total_prob")

#     @assert isapprox(total_prob, 0.5, atol=1e-6) "Test failed: Expected 0.5, got $total_prob"
#     println("Test passed!")
# end

# # Run the test
# test_P_X3_equals_1()

# function create_4node_network()
#     bn = BayesianNetwork{Symbol}()

#     # X1 ~ Bernoulli(0.6)
#     add_stochastic_vertex!(bn, :X1, Bernoulli(0.6), :discrete)

#     # X2 ~ Bernoulli(X1)
#     add_stochastic_vertex!(bn, :X2, (x1) -> Bernoulli(x1), :discrete)
#     add_edge!(bn, :X1, :X2)

#     # X3 ~ Bernoulli(X1)
#     add_stochastic_vertex!(bn, :X3, (x1) -> Bernoulli(x1), :discrete)
#     add_edge!(bn, :X1, :X3)

#     # X4 ~ Bernoulli( (X2==1 && X3==1) ? 0.9 : 0.1 )
#     add_stochastic_vertex!(bn, :X4, (x2, x3) -> Bernoulli((x2==1 && x3==1) ? 0.9 : 0.1), :discrete)
#     add_edge!(bn, :X2, :X4)
#     add_edge!(bn, :X3, :X4)

#     return bn
# end
# function test_P_X4_equals_1()
#     bn = create_4node_network()

#     # Mark X4 = 1 as observed
#     bn.values[:X4] = 1.0
#     bn.is_observed[bn.names_to_ids[:X4]] = true

#     # Identify unobserved discrete nodes
#     unobs_discrete_ids = Int[]
#     for sid in bn.stochastic_ids
#         if !bn.is_observed[sid] && bn.node_types[sid] == :discrete
#             push!(unobs_discrete_ids, sid)
#         end
#     end

#     # Build the log-posterior function
#     log_post = create_log_posterior(bn)

#     # Enumerate over possible assignments for X1, X2, X3
#     results = []
#     for x1 in [0.0, 1.0]
#         for x2 in [0.0, 1.0]
#             for x3 in [0.0, 1.0]
#                 lp = log_post(Dict(:X1 => x1, :X2 => x2, :X3 => x3))
#                 prob = exp(lp)
#                 push!(results, ((x1, x2, x3), prob))
#             end
#         end
#     end

#     # Sum over all configurations to get P(X4 = 1)
#     total_prob = sum(prob for ((_,_,_), prob) in results)

#     println("Results for P(X4 = 1):")
#     for ((x1,x2,x3), prob) in results
#         println("  X1=$x1, X2=$x2, X3=$x3 => contribution = $prob")
#     end
#     println("Total P(X4 = 1): $total_prob")
# end

# test_P_X4_equals_1()
