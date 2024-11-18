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
    ancestral_sampling,
    is_conditionally_independent,
    variable_elimination

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

    @testset "Simple ancestral sampling" begin end

    @testset "Bayes Ball" begin end

    @testset "Variable Elimination Tests" begin
        println("\nTesting Variable Elimination")

        @testset "Simple Chain Network (Z → X → Y)" begin
            # Create a simple chain network: Z → X → Y
            bn = BayesianNetwork{Symbol}()

            # Add vertices with specific distributions
            println("Adding vertices...")
            add_stochastic_vertex!(bn, :Z, Categorical([0.7, 0.3]), false)  # P(Z)
            add_stochastic_vertex!(bn, :X, Normal(0, 1), false)             # P(X|Z)
            add_stochastic_vertex!(bn, :Y, Normal(1, 2), false)             # P(Y|X)

            # Add edges
            println("Adding edges...")
            add_edge!(bn, :Z, :X)
            add_edge!(bn, :X, :Y)

            # Test case 1: P(X | Y=1.5)
            println("\nTest case 1: P(X | Y=1.5)")
            evidence1 = Dict(:Y => 1.5)
            query1 = :X
            result1 = variable_elimination(bn, query1, evidence1)
            @test result1 isa Number
            @test result1 >= 0
            println("P(X | Y=1.5) = ", result1)

            # Test case 2: P(X | Z=1)
            println("\nTest case 2: P(X | Z=1)")
            evidence2 = Dict(:Z => 1)
            query2 = :X
            result2 = variable_elimination(bn, query2, evidence2)
            @test result2 isa Number
            @test result2 >= 0
            println("P(X | Z=1) = ", result2)

            # Test case 3: P(Y | Z=1)
            println("\nTest case 3: P(Y | Z=1)")
            evidence3 = Dict(:Z => 1)
            query3 = :Y
            result3 = variable_elimination(bn, query3, evidence3)
            @test result3 isa Number
            @test result3 >= 0
            println("P(Y | Z=1) = ", result3)
        end

        @testset "Mixed Network (Discrete and Continuous)" begin
            # Create a more complex network with both discrete and continuous variables
            bn = BayesianNetwork{Symbol}()

            # Add vertices
            println("\nAdding vertices for mixed network...")
            add_stochastic_vertex!(bn, :A, Categorical([0.4, 0.6]), false)     # Discrete
            add_stochastic_vertex!(bn, :B, Normal(0, 1), false)                # Continuous
            add_stochastic_vertex!(bn, :C, Categorical([0.3, 0.7]), false)     # Discrete
            add_stochastic_vertex!(bn, :D, Normal(1, 2), false)                # Continuous

            # Add edges: A → B → D ← C
            println("Adding edges...")
            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :D)
            add_edge!(bn, :C, :D)

            # Test case 1: P(B | D=1.0)
            println("\nTest case 1: P(B | D=1.0)")
            evidence1 = Dict(:D => 1.0)
            query1 = :B
            result1 = variable_elimination(bn, query1, evidence1)
            @test result1 isa Number
            @test result1 >= 0
            println("P(B | D=1.0) = ", result1)

            # Test case 2: P(D | A=1, C=1)
            println("\nTest case 2: P(D | A=1, C=1)")
            evidence2 = Dict(:A => 1, :C => 1)
            query2 = :D
            result2 = variable_elimination(bn, query2, evidence2)
            @test result2 isa Number
            @test result2 >= 0
            println("P(D | A=1, C=1) = ", result2)
        end

        @testset "Special Cases" begin
            bn = BayesianNetwork{Symbol}()

            # Single node case
            add_stochastic_vertex!(bn, :X, Normal(0, 1), false)
            result = variable_elimination(bn, :X, Dict{Symbol,Any}())
            @test result isa Number
            @test result >= 0

            # No evidence case
            add_stochastic_vertex!(bn, :Y, Normal(1, 2), false)
            add_edge!(bn, :X, :Y)
            result = variable_elimination(bn, :Y, Dict{Symbol,Any}())
            @test result isa Number
            @test result >= 0
        end
    end
end
