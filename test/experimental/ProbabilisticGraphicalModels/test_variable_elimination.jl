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
@testset "Variable Elimination - Three Node Chain" begin
    # Create Bayesian Network
    bn = BayesianNetwork{Symbol}()
    
    # Node A: Root node with Bernoulli(0.7)
    add_stochastic_vertex!(bn, :A, Bernoulli(0.7), false)
    
    # Node B: Depends on A
    add_stochastic_vertex!(bn, :B, Bernoulli(0.8), false)
    add_edge!(bn, :A, :B)
    
    # Node C: Depends on B
    add_stochastic_vertex!(bn, :C, Bernoulli(0.9), false)
    add_edge!(bn, :B, :C)
    
    # Test marginal distribution of C
    marginal_C = marginal_distribution(bn, :C)
    
    # Verify the result
    expected_prob_C1 = 0.7 * 0.8 * 0.9 + 0.7 * 0.2 * 0.1 + 0.3 * 0.8 * 0.9 + 0.3 * 0.2 * 0.1
    
    @test isapprox(pdf(marginal_C, 1), expected_prob_C1, atol=1e-10)
    @test isapprox(pdf(marginal_C, 0), 1 - expected_prob_C1, atol=1e-10)
    
    # Test conditioning
    bn_conditioned = condition(bn, Dict(:B => 1))
    marginal_C_given_B1 = marginal_distribution(bn_conditioned, :C)
    
    @test isapprox(pdf(marginal_C_given_B1, 1), 0.9, atol=1e-10)
    @test isapprox(pdf(marginal_C_given_B1, 0), 0.1, atol=1e-10)
end