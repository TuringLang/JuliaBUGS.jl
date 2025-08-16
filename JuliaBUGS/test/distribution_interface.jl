using JuliaBUGS
using Distributions
using Random
using Test

@testset "Distribution Interface" begin
    @testset "Simple Model" begin
        # Simple model for testing
        model_def = JuliaBUGS.@bugs begin
            # Priors
            mu ~ dnorm(0, 0.01)  # precision = 1/variance, so 0.01 = 1/100
            sigma ~ dunif(0, 10)

            # Likelihood
            for i in 1:N
                y[i] ~ dnorm(mu, 1/(sigma^2))  # BUGS uses precision
            end
        end

        # Generate some test data
        Random.seed!(123)
        N = 10
        true_mu = 2.0
        true_sigma = 1.5
        y = randn(N) .* true_sigma .+ true_mu

        # Compile the model
        data = (N=N, y=y)
        model = compile(model_def, data)
        model = initialize!(model, (mu=0.0, sigma=1.0))

        # Test the distribution interface
        dist = to_distribution(model)
        @test dist isa JuliaBUGS.Model.BUGSModelDistribution

        # Test sampling
        Random.seed!(456)
        sample1 = rand(dist)
        @test sample1 isa NamedTuple
        @test haskey(sample1, :mu)
        @test haskey(sample1, :sigma)

        sample2 = rand(dist)
        @test sample2 != sample1  # Different samples

        # Test log pdf
        logp = logpdf(dist, sample1)
        @test isfinite(logp)
        @test logp isa Real

        # Test pdf
        p = pdf(dist, sample1)
        @test isfinite(p)
        @test p >= 0
        @test p ≈ exp(logp)

        # Test insupport
        @test insupport(dist, sample1)

        # Test with invalid sample (negative sigma)
        invalid_sample = (mu=0.0, sigma=-1.0)
        @test !insupport(dist, invalid_sample)

        # Test multiple samples
        samples = rand(dist, 5)
        @test length(samples) == 5
        @test all(s -> s isa NamedTuple, samples)

        # Test sampling with dimensions
        samples_2d = rand(dist, (2, 3))
        @test size(samples_2d) == (2, 3)
        @test all(s -> s isa NamedTuple, samples_2d)
    end

    @testset "Hierarchical Model" begin
        # Test with a simpler hierarchical model (BUGS doesn't support nested array indexing)
        hierarchical_model_def = JuliaBUGS.@bugs begin
            # Hierarchical model
            alpha ~ dnorm(0, 0.01)
            tau ~ dgamma(1, 1)

            for j in 1:J
                theta[j] ~ dnorm(alpha, tau)
                y[j] ~ dnorm(theta[j], 1)
            end
        end

        # Generate hierarchical data
        J = 5
        Random.seed!(789)
        y_hierarchical = randn(J) .+ 2.0

        hierarchical_data = (J=J, y=y_hierarchical)
        hierarchical_model = compile(hierarchical_model_def, hierarchical_data)
        hierarchical_model = initialize!(
            hierarchical_model, (alpha=0.0, tau=1.0, theta=zeros(J))
        )

        hierarchical_dist = to_distribution(hierarchical_model)
        @test hierarchical_dist isa JuliaBUGS.Model.BUGSModelDistribution

        hierarchical_sample = rand(hierarchical_dist)
        @test hierarchical_sample isa NamedTuple
        @test haskey(hierarchical_sample, :alpha)
        @test haskey(hierarchical_sample, :tau)
        @test haskey(hierarchical_sample, :theta)
        @test hierarchical_sample.theta isa AbstractVector
        @test length(hierarchical_sample.theta) == J

        hierarchical_logp = logpdf(hierarchical_dist, hierarchical_sample)
        @test isfinite(hierarchical_logp)
        @test hierarchical_logp isa Real
    end
end
