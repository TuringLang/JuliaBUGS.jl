using Test
using Distributions
using Statistics
using JuliaBUGS.ProbabilisticGraphicalModels:
    BayesianNetwork,
    add_stochastic_vertex!,
    add_deterministic_vertex!,
    add_edge!,
    ancestral_sampling,
    is_conditionally_independent

@testset "Sampling and Independence Tests" begin
    @testset "Simple ancestral sampling" begin
        bn = BayesianNetwork{Symbol}()
        # Add stochastic vertices
        add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :B, Normal(1, 2), false, :continuous)
        # Add deterministic vertex C = A + B
        add_deterministic_vertex!(bn, :C, (a, b) -> a + b)
        add_edge!(bn, :A, :C)
        add_edge!(bn, :B, :C)
        samples = ancestral_sampling(bn)
        @test haskey(samples, :A)
        @test haskey(samples, :B)
        @test haskey(samples, :C)
        @test samples[:A] isa Number
        @test samples[:B] isa Number
        @test samples[:C] ≈ samples[:A] + samples[:B]
    end

    @testset "Complex ancestral sampling" begin
        bn = BayesianNetwork{Symbol}()
        add_stochastic_vertex!(bn, :μ, Normal(0, 2), false, :continuous)
        add_stochastic_vertex!(bn, :σ, LogNormal(0, 0.5), false, :continuous)
        add_stochastic_vertex!(bn, :X, Normal(0, 1), false, :continuous)
        add_stochastic_vertex!(bn, :Y, Normal(0, 1), false, :continuous)
        add_deterministic_vertex!(bn, :X_scaled, (μ, σ, x) -> x * σ + μ)
        add_deterministic_vertex!(bn, :Y_scaled, (μ, σ, y) -> y * σ + μ)
        add_deterministic_vertex!(bn, :Sum, (x, y) -> x + y)
        add_deterministic_vertex!(bn, :Product, (x, y) -> x * y)
        add_deterministic_vertex!(bn, :N, () -> 2.0)
        add_deterministic_vertex!(bn, :Mean, (s, n) -> s / n)
        add_edge!(bn, :μ, :X_scaled)
        add_edge!(bn, :σ, :X_scaled)
        add_edge!(bn, :X, :X_scaled)
        add_edge!(bn, :μ, :Y_scaled)
        add_edge!(bn, :σ, :Y_scaled)
        add_edge!(bn, :Y, :Y_scaled)
        add_edge!(bn, :X_scaled, :Sum)
        add_edge!(bn, :Y_scaled, :Sum)
        add_edge!(bn, :X_scaled, :Product)
        add_edge!(bn, :Y_scaled, :Product)
        add_edge!(bn, :Sum, :Mean)
        add_edge!(bn, :N, :Mean)
        samples = ancestral_sampling(bn)

        @test all(
            haskey(samples, k) for
            k in [:μ, :σ, :X, :Y, :X_scaled, :Y_scaled, :Sum, :Product, :Mean, :N]
        )

        @test all(samples[k] isa Number for k in keys(samples))
        @test samples[:X_scaled] ≈ samples[:X] * samples[:σ] + samples[:μ]
        @test samples[:Y_scaled] ≈ samples[:Y] * samples[:σ] + samples[:μ]
        @test samples[:Sum] ≈ samples[:X_scaled] + samples[:Y_scaled]
        @test samples[:Product] ≈ samples[:X_scaled] * samples[:Y_scaled]
        @test samples[:Mean] ≈ samples[:Sum] / samples[:N]
        @test samples[:N] ≈ 2.0
        @test samples[:σ] > 0
        # Multiple samples test
        n_samples = 1000
        means = zeros(n_samples)
        for i in 1:n_samples
            samples = ancestral_sampling(bn)
            means[i] = samples[:Mean]
        end

        @test mean(means) ≈ 0 atol = 0.5
        @test std(means) > 0
    end

    @testset "Bayes Ball" begin
        @testset "Chain Structure (A → B → C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)

            @test is_conditionally_independent(bn, :A, :C, [:B])
            @test !is_conditionally_independent(bn, :A, :C, Symbol[])
        end

        @testset "Fork Structure (A ← B → C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :B, :A)
            add_edge!(bn, :B, :C)

            @test is_conditionally_independent(bn, :A, :C, [:B])
        end

        @testset "Collider Structure (A → B ← C)" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(), false, :continuous)

            add_edge!(bn, :A, :B)
            add_edge!(bn, :C, :B)

            @test is_conditionally_independent(bn, :A, :C, Symbol[])
            @test !is_conditionally_independent(bn, :A, :C, [:B])
        end

        @testset "Bayes Ball Algorithm Tests" begin
            # Create a simple network: A → B → C
            bn = BayesianNetwork{Symbol}()
            add_stochastic_vertex!(bn, :A, Normal(0, 1), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(0, 1), false, :continuous)
            add_stochastic_vertex!(bn, :C, Normal(0, 1), false, :continuous)
            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)
            @testset "Corner Case: X or Y in Z" begin
                # Test case where X is in Z
                @test is_conditionally_independent(bn, :A, :C, [:A])  # A ⊥ C | A
                # Test case where Y is in Z
                @test is_conditionally_independent(bn, :A, :C, [:C])  # A ⊥ C | C
                # Test case where both X and Y are in Z
                @test is_conditionally_independent(bn, :A, :C, [:A, :C])  # A ⊥ C | A, C
            end
        end

        @testset "Complex Structure" begin
            bn = BayesianNetwork{Symbol}()

            for v in [:A, :B, :C, :D, :E]
                add_stochastic_vertex!(bn, v, Normal(), false, :continuous)
            end

            # Create structure:
            #     A → B → D
            #         ↓   ↑
            #         C → E
            add_edge!(bn, :A, :B)
            add_edge!(bn, :B, :C)
            add_edge!(bn, :B, :D)
            add_edge!(bn, :C, :E)
            add_edge!(bn, :E, :D)

            @test is_conditionally_independent(bn, :A, :E, [:B, :C])
            @test !is_conditionally_independent(bn, :A, :E, Symbol[])
        end

        @testset "Error Handling" begin
            bn = BayesianNetwork{Symbol}()

            add_stochastic_vertex!(bn, :A, Normal(), false, :continuous)
            add_stochastic_vertex!(bn, :B, Normal(), false, :continuous)
            @test_throws KeyError is_conditionally_independent(bn, :A, :B, [:NonExistent])
        end
    end

    @testset "Conditional Independence (Single and Multiple Variables)" begin
        bn = BayesianNetwork{Symbol}()

        # Create a complex network
        #     A → B → D
        #     ↓   ↓   ↑
        #     C → E → F
        for v in [:A, :B, :C, :D, :E, :F]
            add_stochastic_vertex!(bn, v, Normal(), false, :continuous)
        end

        add_edge!(bn, :A, :B)
        add_edge!(bn, :A, :C)
        add_edge!(bn, :B, :D)
        add_edge!(bn, :B, :E)
        add_edge!(bn, :C, :E)
        add_edge!(bn, :E, :F)
        add_edge!(bn, :F, :D)

        # Test single variable independence
        @test is_conditionally_independent(bn, :A, :F, [:B, :C])
        @test !is_conditionally_independent(bn, :A, :D, Symbol[])

        # Test multiple variable independence
        @test is_conditionally_independent(bn, [:A], [:F], [:B, :C])
        @test is_conditionally_independent(bn, [:A, :B], [:F], [:C, :E])
        @test !is_conditionally_independent(bn, [:A, :B], [:D, :F], Symbol[])

        # Test when some variables are in conditioning set
        @test is_conditionally_independent(bn, [:A, :B], [:D, :F], [:A])
        @test is_conditionally_independent(bn, [:A, :B], [:D, :F], [:F])

        # Test error handling
        @test_throws KeyError is_conditionally_independent(
            bn, [:A, :NonExistent], [:F], [:B]
        )
        @test_throws KeyError is_conditionally_independent(
            bn, [:A], [:F, :NonExistent], [:B]
        )
        @test_throws KeyError is_conditionally_independent(bn, [:A], [:F], [:NonExistent])
        @test_throws ArgumentError is_conditionally_independent(bn, Symbol[], [:F], [:B])
        @test_throws ArgumentError is_conditionally_independent(bn, [:A], Symbol[], [:B])
    end
end
