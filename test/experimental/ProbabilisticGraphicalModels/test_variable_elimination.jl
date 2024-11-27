# 1. First, activate the package environment
using Pkg
Pkg.activate(".")

# 2. Load required packages
using Test
using Distributions
using Graphs
using BangBang  # This is needed based on the imports

# 3. Load JuliaBUGS and its submodule
using JuliaBUGS
using JuliaBUGS.ProbabilisticGraphicalModels
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    condition!,
    decondition,
    ancestral_sampling,
    is_conditionally_independent, 
    marginal_distribution,
    eliminate_variables
# 4. Run the specific test

@testset "Simple Discrete Chain" begin
    bn = BayesianNetwork{Symbol}()
    
    # Simple chain A -> B -> C
    add_stochastic_vertex!(bn, :A, Bernoulli(0.7), false)
    add_stochastic_vertex!(bn, :B, Bernoulli(0.8), false)
    add_stochastic_vertex!(bn, :C, Bernoulli(0.9), false)
    
    add_edge!(bn, :A, :B)
    add_edge!(bn, :B, :C)
    
    ordered_vertices = topological_sort_by_dfs(bn.graph)
    println(ordered_vertices)
    marginal_C = marginal_distribution(bn, :C)
    println(marginal_C)
end

# @testset "Mixed Graph - Variable Elimination" begin
#     bn = BayesianNetwork{Symbol}()
    
#     # X1 ~ Uniform(0,1)
#     add_stochastic_vertex!(bn, :X1, Uniform(0, 1), false)
    
#     # X2 ~ Bernoulli(X1)
#     # We need a function that creates a new Bernoulli distribution based on X1's value
#     add_deterministic_vertex!(bn, :X2_dist, x1 -> Bernoulli(x1))
#     add_stochastic_vertex!(bn, :X2, Bernoulli(0.5), false)  # Initial dist doesn't matter
#     add_edge!(bn, :X1, :X2_dist)
#     add_edge!(bn, :X2_dist, :X2)
    
#     # X3 ~ Normal(μ(X2), 1)
#     # Function that creates a new Normal distribution based on X2's value
#     add_deterministic_vertex!(bn, :X3_dist, x2 -> Normal(x2 == 1 ? 10.0 : 2.0, 1.0))
#     add_stochastic_vertex!(bn, :X3, Normal(0, 1), false)  # Initial dist doesn't matter
#     add_edge!(bn, :X2, :X3_dist)
#     add_edge!(bn, :X3_dist, :X3)
# end

@testset "Mixed Graph - Variable Elimination" begin
    bn = BayesianNetwork{Symbol}()
    
    # X1 ~ Uniform(0,1)
    add_stochastic_vertex!(bn, :X1, Uniform(0, 1), false)
    
    # X2 ~ Bernoulli(X1)
    # The distribution constructor takes the parent value and returns the appropriate distribution
    conditional_dist_X2 = x1 -> Bernoulli(x1)
    add_stochastic_vertex!(bn, :X2, conditional_dist_X2, false)
    add_edge!(bn, :X1, :X2)
    
    # X3 ~ Normal(μ(X2), 1)
    conditional_dist_X3 = x2 -> Normal(x2 == 1 ? 10.0 : 2.0, 1.0)
    add_stochastic_vertex!(bn, :X3, conditional_dist_X3, false)
    add_edge!(bn, :X2, :X3)
end