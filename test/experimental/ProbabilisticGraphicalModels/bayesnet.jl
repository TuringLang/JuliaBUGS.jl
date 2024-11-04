using Test
using Distributions
using Graphs
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    condition,
    decondition,
    ancestral_sampling
@testset "BayesianNetwork" begin
    @testset "Adding vertices" begin
        bn = BayesianNetwork{Symbol}()

        # Test adding stochastic vertex
        id1 = add_stochastic_vertex!(bn, :A, Normal(0, 1), false)
        @test id1 == 1
        @test length(bn.names) == 1
        @test bn.names[1] == :A
        @test bn.names_to_ids[:A] == 1
        @test bn.is_stochastic[1] == true
        @test bn.is_observed[1] == false
        @test length(bn.stochastic_ids) == 1

        # Test adding deterministic vertex
        f(x) = x^2
        id2 = add_deterministic_vertex!(bn, :B, f)
        @test id2 == 2
        @test length(bn.names) == 2
        @test bn.names[2] == :B
        @test bn.names_to_ids[:B] == 2
        @test bn.is_stochastic[2] == false
        @test bn.is_observed[2] == false
        @test length(bn.deterministic_ids) == 1
    end

    @testset "Adding edges" begin
        bn = BayesianNetwork{Symbol}()
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false)
        add_stochastic_vertex!(bn, :B, Normal(0, 1), false)

        add_edge!(bn, :A, :B)
        @test has_edge(bn.graph, 1, 2)
    end

    @testset "conditioning and deconditioning" begin
        bn = BayesianNetwork{Symbol}()
        # Add some vertices
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false)
        add_stochastic_vertex!(bn, :B, Normal(0, 1), false)
        add_stochastic_vertex!(bn, :C, Normal(0, 1), false)

        # Test conditioning
        bn_cond = condition(bn, Dict(:A => 1.0))
        @test bn_cond.is_observed[1] == true
        @test bn_cond.values[:A] == 1.0
        @test bn_cond.is_observed[2] == false
        @test bn_cond.is_observed[3] == false

        # Ensure original bn is not mutated
        @test bn.is_observed[1] == false
        @test !haskey(bn.values, :A)

        # Test conditioning multiple variables
        bn_cond2 = condition(bn_cond, Dict(:B => 2.0))
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.is_observed[2] == true
        @test bn_cond2.values[:A] == 1.0
        @test bn_cond2.values[:B] == 2.0

        # Ensure bn_cond is not mutated
        @test bn_cond.is_observed[2] == false
        @test !haskey(bn_cond.values, :B)

        # Test deconditioning
        bn_decond = decondition(bn_cond2, [:A])
        @test bn_decond.is_observed[1] == false
        @test bn_decond.is_observed[2] == true
        @test !haskey(bn_decond.values, :A)
        @test bn_decond.values[:B] == 2.0

        # Ensure bn_cond2 is not mutated
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.values[:A] == 1.0

        # Test deconditioning all
        bn_decond_all = decondition(bn_cond2)
        @test all(.!bn_decond_all.is_observed)
        @test all(values(bn_decond_all.values) .=== nothing)

        # Ensure bn_cond2 is still not mutated
        @test bn_cond2.is_observed[1] == true
        @test bn_cond2.is_observed[2] == true
        @test bn_cond2.values[:A] == 1.0
        @test bn_cond2.values[:B] == 2.0
    end

    @testset "Simple ancestral sampling" begin
        # Create a Bayesian network
        bn = BayesianNetwork{Symbol}()
    
        # Add stochastic vertices with their distributions
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false)  # Stochastic variable A
        add_stochastic_vertex!(bn, :B, Normal(0, 1), false)  # Stochastic variable B
        add_stochastic_vertex!(bn, :C, Normal(0, 1), false)  # Stochastic variable C
    
        # Add edges to define relationships
        add_edge!(bn, :A, :B)  # A -> B
        add_edge!(bn, :A, :C)  # A -> C
    
        # Perform ancestral sampling
        samples = ancestral_sampling(bn)
    
        # Debugging: Print samples to see its contents
        println("Samples: ", samples)
    
        # Check if all sampled variables are present
        @test haskey(samples, :A)
        @test haskey(samples, :B)
        @test haskey(samples, :C)
    
        # Check if the values are numerical since we are sampling from Normal distributions
        @test isa(samples[:A], Number)
        @test isa(samples[:B], Number)
        @test isa(samples[:C], Number)
    end
    

    @testset "Bayes Ball" begin end
end
