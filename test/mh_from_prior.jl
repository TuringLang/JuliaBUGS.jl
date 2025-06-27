using Test
using JuliaBUGS
using JuliaBUGS: @bugs, compile, @varname, MHFromPrior, MHFromPriorState, gibbs_internal
using JuliaBUGS.Model: condition
using AbstractMCMC
using Random
using Statistics

@testset "MHFromPrior" begin
    @testset "Standalone MHFromPrior targeting posterior" begin
        # Create a simple model where we know the posterior
        # Model: p ~ Beta(2, 2), y[i] ~ Bernoulli(p)
        # With y = [1,1,1,0,0,0,0,0,0,0] (3 successes, 7 failures)
        # Posterior: Beta(2+3, 2+7) = Beta(5, 9)
        # Expected posterior mean: 5/(5+9) = 5/14 ≈ 0.357

        model_def = @bugs begin
            p ~ Beta(2, 2)
            for i in 1:N
                y[i] ~ Bernoulli(p)
            end
        end

        y_data = [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]  # 3 successes, 7 failures
        model = compile(model_def, (; N=10, y=y_data))

        # Sample using MHFromPrior
        rng = Random.MersenneTwister(123)
        chain = sample(rng, model, MHFromPrior(), 100000)

        # Extract samples
        p_samples = vec([nt.p for nt in chain[50000:end]])  # Extract first parameter (p)

        # Check posterior mean
        posterior_mean = mean(p_samples)
        expected_mean = 5 / 14  # Beta(5, 9) mean
        @test isapprox(posterior_mean, expected_mean, atol=0.035)

        # Check that it's not sampling from prior
        prior_mean = 0.5  # Beta(2, 2) mean
        @test abs(posterior_mean - expected_mean) < abs(posterior_mean - prior_mean)

        # Test posterior variance
        posterior_var = var(p_samples)
        expected_var = (5 * 9) / ((5 + 9)^2 * (5 + 9 + 1))  # Beta(5, 9) variance
        @test isapprox(posterior_var, expected_var, atol=0.01)
    end

    @testset "MHFromPrior with discrete parameters" begin
        # Model with discrete parameter
        model_def = @bugs begin
            # Discrete parameter with categorical prior
            k ~ Categorical(p_cat)

            # Use array indexing to select mean based on k
            mu = mu_values[k]

            # Observations
            for i in 1:N
                y[i] ~ Normal(mu, 0.1)
            end
        end

        # Generate data from k=3 (mu=1.0)
        N = 100
        y_data = randn(N) .* 0.1 .+ 1.0
        p_cat = [0.2, 0.3, 0.5]
        mu_values = [-1.0, 0.0, 1.0]  # means for k=1,2,3
        model = compile(model_def, (; N=N, y=y_data, p_cat=p_cat, mu_values=mu_values))

        # Sample
        rng = Random.MersenneTwister(456)
        chain = sample(rng, model, MHFromPrior(), 5000)

        # Check that k=3 is most frequent
        k_samples = vec([nt.k for nt in chain])  # Extract k parameter
        k_counts = [count(==(i), k_samples) for i in 1:3]
        @test argmax(k_counts) == 3

        # Should have very low probability of k=1 or k=2
        @test k_counts[1] / length(k_samples) < 0.1
        @test k_counts[2] / length(k_samples) < 0.2
    end

    @testset "MHFromPrior initial parameters" begin
        model_def = @bugs begin
            theta ~ Normal(0, 1)
            y ~ Normal(theta, 0.1)
        end

        model = compile(model_def, (; y=2.0))

        # Test with custom initial parameters
        rng = Random.MersenneTwister(789)
        initial_params = [5.0]  # Far from posterior

        chain = sample(rng, model, MHFromPrior(), 1000; initial_params=initial_params)

        # Should converge to near y=2.0 despite starting at 5.0
        theta_samples = vec([nt.theta for nt in chain[500:end]])  # Extract theta parameter
        @test isapprox(mean(theta_samples), 2.0, atol=0.1)
    end

    @testset "MHFromPrior state consistency" begin
        model_def = @bugs begin
            mu ~ Normal(0, 10)
            sigma ~ truncated(Normal(1, 1), 0, Inf)
            for i in 1:N
                y[i] ~ Normal(mu, sigma)
            end
        end

        y_data = randn(5) .+ 3.0
        model = compile(model_def, (; N=5, y=y_data))

        # Manually step through sampling
        rng = Random.MersenneTwister(111)
        logdensitymodel = AbstractMCMC.LogDensityModel(model)

        # Initial step
        sample1, state1 = AbstractMCMC.step(rng, logdensitymodel, MHFromPrior())
        @test state1 isa MHFromPriorState
        @test haskey(state1.evaluation_env, :mu)
        @test haskey(state1.evaluation_env, :sigma)
        @test state1.logp isa Real

        # Check that evaluation_env is properly set
        @test sample1 == state1.evaluation_env

        # Subsequent step
        sample2, state2 = AbstractMCMC.step(rng, logdensitymodel, MHFromPrior(), state1)

        # If proposal was rejected, state should be unchanged
        if sample2 == sample1
            @test state2 === state1
        else
            # If accepted, state should be updated
            @test state2.evaluation_env == sample2
            @test state2.logp != state1.logp
        end
    end

    @testset "MHFromPrior within Gibbs" begin
        # This will be tested more thoroughly in gibbs.jl tests
        # Here we just verify the gibbs_internal function works

        model_def = @bugs begin
            p ~ Beta(1, 1)
            lambda ~ Gamma(2, 2)
            for i in 1:N
                x[i] ~ Bernoulli(p)
                y[i] ~ Poisson(lambda)
            end
        end

        N = 10
        x_data = rand(0:1, N)
        y_data = rand(1:5, N)
        model = compile(model_def, (; N=N, x=x_data, y=y_data))

        # Create a conditioned model (condition on lambda)
        using JuliaBUGS.Model: condition
        cond_model = condition(model, (; lambda=2.0))

        # Test gibbs_internal
        rng = Random.MersenneTwister(222)
        param_values = gibbs_internal(rng, cond_model, MHFromPrior())
        
        # Check that the returned value is a tuple (sample, state/logp)
        @test param_values isa Tuple
        
        # The first element should be a NamedTuple containing the sampled parameters
        @test param_values[1] isa NamedTuple
        # Since we conditioned on lambda, we expect to get p sampled
        @test haskey(param_values[1], :p)
        # Confirm p itself is a Float64 value
        @test param_values[1].p isa Float64
    end
end
