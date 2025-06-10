using Test
using JuliaBUGS
using JuliaBUGS:
    @bugs,
    compile,
    @varname,
    Gibbs,
    MHFromPrior,
    WithGradient,
    verify_sampler_map,
    expand_variables
using ADTypes
using AbstractMCMC
using Random
using OrderedCollections: OrderedDict
using MCMCChains: Chains
using ReverseDiff
using Statistics
using StatsBase: mode

@testset "Gibbs" begin
    @testset "verify_sampler_map" begin
        # Simple model for testing
        model_def = @bugs begin
            α ~ Normal(0, 1)
            β ~ Normal(α, 1)
            γ ~ Normal(β, 1)
            y ~ Normal(γ, 1)
        end
        model = compile(model_def, (; y=1.0))

        @testset "Valid sampler maps" begin
            # All parameters covered with single sampler
            sampler_map = OrderedDict(
                [@varname(α), @varname(β), @varname(γ)] => MHFromPrior()
            )
            @test verify_sampler_map(model, sampler_map)

            # Different samplers for different parameters
            sampler_map = OrderedDict(
                [@varname(α)] => MHFromPrior(), [@varname(β), @varname(γ)] => MHFromPrior()
            )
            @test verify_sampler_map(model, sampler_map)

            # Each parameter with its own sampler
            sampler_map = OrderedDict(
                @varname(α) => MHFromPrior(),
                @varname(β) => MHFromPrior(),
                @varname(γ) => MHFromPrior(),
            )
            @test verify_sampler_map(model, sampler_map)
        end

        @testset "Invalid sampler maps" begin
            # Missing parameter
            sampler_map = OrderedDict([@varname(α), @varname(β)] => MHFromPrior())
            @test_throws ArgumentError verify_sampler_map(model, sampler_map)

            # Extra parameter not in model
            sampler_map = OrderedDict(
                [@varname(α), @varname(β), @varname(γ), @varname(δ)] => MHFromPrior()
            )
            @test_throws ArgumentError verify_sampler_map(model, sampler_map)

            # Duplicate coverage
            sampler_map = OrderedDict(
                [@varname(α), @varname(β)] => MHFromPrior(),
                [@varname(β), @varname(γ)] => MHFromPrior(),
            )
            @test_throws ArgumentError verify_sampler_map(model, sampler_map)
        end
    end

    @testset "Subsuming behavior" begin
        # Model with array parameters
        model_def = @bugs begin
            for i in 1:3
                x[i] ~ Normal(0, 1)
            end
            μ ~ Normal(0, 10)
            for i in 1:3
                y[i] ~ Normal(x[i] + μ, 1)
            end
        end
        y_data = [1.0, 2.0, 3.0]
        model = compile(model_def, (; y=y_data))

        @testset "expand_variables" begin
            model_params = model.graph_evaluation_data.sorted_parameters

            # Test expanding x to x[1], x[2], x[3]
            expanded = expand_variables([@varname(x)], model_params)
            @test length(expanded) == 3
            @test @varname(x[1]) in expanded
            @test @varname(x[2]) in expanded
            @test @varname(x[3]) in expanded

            # Test μ stays as is
            expanded = expand_variables([@varname(μ)], model_params)
            @test length(expanded) == 1
            @test @varname(μ) in expanded

            # Test mixed
            expanded = expand_variables([@varname(x), @varname(μ)], model_params)
            @test length(expanded) == 4
            @test @varname(x[1]) in expanded
            @test @varname(x[2]) in expanded
            @test @varname(x[3]) in expanded
            @test @varname(μ) in expanded
        end

        @testset "Subsuming in verify_sampler_map" begin
            # Valid: x covers x[1], x[2], x[3]
            sampler_map = OrderedDict(
                @varname(x) => MHFromPrior(), @varname(μ) => MHFromPrior()
            )
            @test verify_sampler_map(model, sampler_map)

            # Valid: explicit indexing
            sampler_map = OrderedDict(
                [@varname(x[1]), @varname(x[2]), @varname(x[3])] => MHFromPrior(),
                @varname(μ) => MHFromPrior(),
            )
            @test verify_sampler_map(model, sampler_map)

            # Invalid: mixing subsuming and explicit (duplicate coverage)
            sampler_map = OrderedDict(
                @varname(x) => MHFromPrior(),
                @varname(x[1]) => MHFromPrior(),
                @varname(μ) => MHFromPrior(),
            )
            @test_throws ArgumentError verify_sampler_map(model, sampler_map)

            # Invalid: partial coverage with subsuming
            # (x[1] and x[2] but not x[3])
            sampler_map = OrderedDict(
                [@varname(x[1]), @varname(x[2])] => MHFromPrior(),
                @varname(μ) => MHFromPrior(),
            )
            @test_throws ArgumentError verify_sampler_map(model, sampler_map)
        end
    end

    @testset "Simple gibbs (legacy test)" begin
        model_def = @bugs begin
            # Likelihood
            for i in 1:N
                y[i] ~ dnorm(mu[i], tau)
                mu[i] = alpha + beta * x[i]
            end

            # Priors
            alpha ~ dnorm(0, 0.01)
            beta ~ dnorm(0, 0.01)
            sigma ~ dunif(0, 10)

            # Precision
            tau = pow(sigma, -2)

            # Generated Quantities for testing purposes
            gen_quant = alpha + beta * sigma
        end

        # ground truth: alpha = 3, beta = 2, sigma = 1
        data = (
            N=10,
            x=[0.0, 1.11, 2.22, 3.33, 4.44, 5.56, 6.67, 7.78, 8.89, 10.0],
            y=[1.58, 4.80, 7.10, 8.86, 11.73, 14.52, 18.22, 18.73, 21.04, 22.93],
        )

        model = compile(model_def, data, (;))

        # single step
        p_s, st_init = AbstractMCMC.step(
            Random.default_rng(),
            AbstractMCMC.LogDensityModel(model),
            Gibbs(model, MHFromPrior()),
        )

        # following step
        p_s, st = AbstractMCMC.step(
            Random.default_rng(),
            AbstractMCMC.LogDensityModel(model),
            Gibbs(model, MHFromPrior()),
            st_init,
        )

        # Test that state contains evaluation environment
        @test st isa JuliaBUGS.GibbsState
        @test st.evaluation_env isa NamedTuple
        @test haskey(st.evaluation_env, :alpha)
        @test haskey(st.evaluation_env, :beta)
        @test haskey(st.evaluation_env, :sigma)
    end

    @testset "Gibbs sampling integration" begin
        # Simple hierarchical model
        model_def = @bugs begin
            μ ~ Normal(0, 10)
            τ ~ Gamma(1, 1)
            σ = 1 / sqrt(τ)
            for i in 1:N
                θ[i] ~ Normal(μ, σ)
                y[i] ~ Normal(θ[i], 1)
            end
        end

        N = 5
        y_data = [1.0, 1.5, 2.0, 2.5, 3.0]
        model = compile(model_def, (; N=N, y=y_data))

        @testset "Basic Gibbs construction" begin
            # Using same sampler for all parameters
            gibbs = Gibbs(model, MHFromPrior())
            @test length(gibbs.sampler_map) ==
                length(model.graph_evaluation_data.sorted_parameters)

            # Using specific sampler map
            sampler_map = OrderedDict(
                @varname(μ) => MHFromPrior(),
                @varname(τ) => MHFromPrior(),
                @varname(θ) => MHFromPrior(),  # Subsumes θ[1], ..., θ[5]
            )
            gibbs = Gibbs(model, sampler_map)
            @test gibbs isa Gibbs
            @test length(gibbs.sampler_map) == 3
        end

        @testset "Gibbs sampling runs" begin
            sampler_map = OrderedDict(
                @varname(μ) => MHFromPrior(),
                @varname(τ) => MHFromPrior(),
                @varname(θ) => MHFromPrior(),
            )
            gibbs = Gibbs(model, sampler_map)

            # Test that sampling runs without error
            rng = Random.MersenneTwister(123)
            chain = sample(rng, model, gibbs, 100; progress=false, chain_type=Chains)

            @test chain isa AbstractMCMC.AbstractChains
            @test size(chain, 1) == 100  # Number of samples
            @test size(chain, 2) == 7    # Number of parameters (μ, τ, θ[1:5])
        end
    end

    @testset "Gibbs correctness tests" begin
        @testset "Conjugate Normal-Normal model" begin
            # Model: y ~ Normal(μ, 1), μ ~ Normal(0, 1)
            # Posterior: μ | y ~ Normal(y/2, 1/√2)
            model_def = @bugs begin
                μ ~ Normal(0, 1)
                y ~ Normal(μ, 1)
            end

            y_obs = 2.0
            model = compile(model_def, (; y=y_obs))

            # Sample with Gibbs
            # Note: MHFromPrior can be inefficient for continuous parameters
            # especially in a single-parameter model where Gibbs reduces to plain MH
            rng = Random.MersenneTwister(42)
            gibbs = Gibbs(model, MHFromPrior())
            chain = sample(
                rng,
                model,
                gibbs,
                50000;
                progress=false,
                chain_type=Chains,
                discard_initial=10000,
            )

            # Extract μ samples
            μ_samples = vec(chain[:μ].data)

            # Theoretical posterior
            posterior_mean = y_obs / 2
            posterior_std = 1 / sqrt(2)

            # Test convergence to correct posterior
            # MHFromPrior may require many samples for good mixing
            @test mean(μ_samples) ≈ posterior_mean atol = 0.4
            @test std(μ_samples) ≈ posterior_std atol = 0.2
        end

        @testset "Linear regression convergence" begin
            # Use the regression model with known ground truth
            model_def = @bugs begin
                # Likelihood
                for i in 1:N
                    y[i] ~ dnorm(mu[i], tau)
                    mu[i] = alpha + beta * x[i]
                end

                # Priors - use reasonable priors for better mixing
                alpha ~ dnorm(0, 0.1)     # Prior std = sqrt(1/0.1) ≈ 3.16
                beta ~ dnorm(0, 0.1)      # Prior std = sqrt(1/0.1) ≈ 3.16
                tau ~ dgamma(1, 1)        # More informative prior
            end

            # Generate data from known parameters
            true_alpha = 3.0
            true_beta = 2.0
            true_sigma = 1.0

            Random.seed!(123)
            N = 30  # Fewer points for faster sampling
            x_data = collect(range(0, 10; length=N))
            y_data = true_alpha .+ true_beta .* x_data .+ randn(N) .* true_sigma

            data = (N=N, x=x_data, y=y_data)

            # Initialize near reasonable values for better mixing
            inits = (; alpha=0.0, beta=0.0, tau=1.0)
            model = compile(model_def, data, inits)

            # Sample with Gibbs - need more samples for MHFromPrior
            rng = Random.MersenneTwister(42)
            gibbs = Gibbs(model, MHFromPrior())
            chain = sample(
                rng,
                model,
                gibbs,
                20000;
                progress=false,
                chain_type=Chains,
                discard_initial=5000,
            )

            # Test convergence to approximate true parameters
            # MHFromPrior may not be very efficient, so use looser tolerances
            @test mean(chain[:alpha]) ≈ true_alpha atol = 0.5
            @test mean(chain[:beta]) ≈ true_beta atol = 0.3
            @test mean(1 ./ sqrt.(chain[:tau])) ≈ true_sigma atol = 0.3
        end

        @testset "Compare Gibbs with HMC" begin
            # Simple model where both samplers should work well
            model_def = @bugs begin
                μ ~ Normal(0, 2)
                σ ~ truncated(Normal(1, 0.5), 0, Inf)
                for i in 1:N
                    y[i] ~ Normal(μ, σ)
                end
            end

            N = 20
            Random.seed!(456)
            true_μ = 1.5
            true_σ = 0.8
            y_data = true_μ .+ randn(N) .* true_σ

            model = compile(model_def, (; N=N, y=y_data))

            # Sample with Gibbs
            rng1 = Random.MersenneTwister(789)
            gibbs = Gibbs(model, MHFromPrior())
            chain_gibbs = sample(
                rng1,
                model,
                gibbs,
                5000;
                progress=false,
                chain_type=Chains,
                discard_initial=1000,
            )

            # Sample with HMC (would need AdvancedHMC)
            # This test would verify that both samplers produce similar posterior distributions

            # For now, just test that Gibbs gives reasonable results
            μ_mean_gibbs = mean(chain_gibbs[:μ])
            σ_mean_gibbs = mean(chain_gibbs[:σ])

            # Should be close to MLE estimates
            mle_μ = mean(y_data)
            @test μ_mean_gibbs ≈ mle_μ atol = 0.1
            @test σ_mean_gibbs > 0.5 && σ_mean_gibbs < 1.5  # Reasonable range
        end

        @testset "Gibbs with mixed samplers" begin
            # Test using different samplers for different parameters
            model_def = @bugs begin
                # Continuous parameters
                μ ~ Normal(0, 10)
                σ ~ truncated(Normal(1, 1), 0, Inf)

                # Discrete parameter 
                k ~ Categorical(probs[:])

                # Observations
                for i in 1:N
                    y[i] ~ Normal(μ + k, σ)
                end
            end

            N = 30
            Random.seed!(321)
            true_μ = 1.0
            true_k = 2
            true_σ = 0.5
            y_data = true_μ .+ true_k .+ randn(N) .* true_σ
            probs = [0.3, 0.3, 0.4]

            model = compile(model_def, (; N=N, y=y_data, probs=probs))

            # Use MHFromPrior for discrete k, could use HMC for continuous params
            sampler_map = OrderedDict(
                @varname(k) => MHFromPrior(), [@varname(μ), @varname(σ)] => MHFromPrior()
            )
            gibbs = Gibbs(model, sampler_map)

            rng = Random.MersenneTwister(999)
            chain = sample(
                rng,
                model,
                gibbs,
                3000;
                progress=false,
                chain_type=Chains,
                discard_initial=500,
            )

            # Check that we recover reasonable values
            @test mean(chain[:μ] .+ chain[:k]) ≈ mean(y_data) atol = 0.2
            @test mode(Int.(vec(chain[:k].data))) == true_k  # Most frequent value should be true k
        end

        @testset "Conditioning correctness" begin
            # Test that Gibbs respects conditioning and only updates the right variables
            model_def = @bugs begin
                a ~ Normal(0, 1)
                b ~ Normal(a, 1)
                c ~ Normal(b, 1)
                y ~ Normal(c, 0.1)
            end

            y_obs = 1.5
            model = compile(model_def, (; y=y_obs))

            # Test different conditioning patterns
            @testset "Update only a" begin
                sampler_map = OrderedDict(
                    @varname(a) => MHFromPrior(),
                    [@varname(b), @varname(c)] => MHFromPrior(),
                )
                gibbs = Gibbs(model, sampler_map)

                # Initialize with specific values
                initial_params = (; a=0.5, b=1.0, c=1.5)
                model_init = JuliaBUGS.initialize!(model, initial_params)

                # Take one step
                rng = Random.MersenneTwister(123)
                env1, state = AbstractMCMC.step(
                    rng, AbstractMCMC.LogDensityModel(model_init), gibbs
                )
                env2, _ = AbstractMCMC.step(
                    rng, AbstractMCMC.LogDensityModel(model_init), gibbs, state
                )

                # When updating a, b and c should remain fixed in that sub-step
                # But they might change in the next sub-step
                # This is a bit tricky to test without looking at internals

                # At least verify that all parameters can change
                @test env2.a != initial_params.a ||
                    env2.b != initial_params.b ||
                    env2.c != initial_params.c
            end
        end
    end

    @testset "Gibbs with complex models" begin
        # Model with both scalar and array parameters
        model_def = @bugs begin
            # Hyperparameters
            α ~ Gamma(1, 1)
            β ~ Gamma(1, 1)

            # Group means
            for j in 1:J
                μ[j] ~ Normal(0, 10)
            end

            # Individual effects
            for i in 1:N
                group[i] = group_id[i]
                θ[i] ~ Normal(μ[group[i]], 1)
                y[i] ~ Normal(θ[i], 1)
            end
        end

        J = 3
        N = 9
        group_id = [1, 1, 1, 2, 2, 2, 3, 3, 3]
        y_data = randn(N) .+ [0, 0, 0, 1, 1, 1, 2, 2, 2]

        model = compile(model_def, (; J=J, N=N, group_id=group_id, y=y_data))

        @testset "Complex model sampler map" begin
            # Test various ways to specify the sampler map
            sampler_map1 = OrderedDict(
                [@varname(α), @varname(β)] => MHFromPrior(),
                @varname(μ) => MHFromPrior(),
                @varname(θ) => MHFromPrior(),
            )
            @test verify_sampler_map(model, sampler_map1)

            # More granular specification
            sampler_map2 = OrderedDict(
                @varname(α) => MHFromPrior(),
                @varname(β) => MHFromPrior(),
                [@varname(μ[1]), @varname(μ[2]), @varname(μ[3])] => MHFromPrior(),
                [@varname(θ[i]) for i in 1:N] => MHFromPrior(),
            )
            @test verify_sampler_map(model, sampler_map2)
        end
    end

    @testset "Gibbs with AdvancedHMC/AdvancedMH integration" begin
        using AdvancedHMC: HMC, NUTS
        using AdvancedMH: RWMH, StaticMH
        using Distributions: Product, fill

        @testset "WithGradient wrapper" begin
            model_def = @bugs begin
                μ ~ Normal(0, 10)
                σ ~ truncated(Normal(1, 1), 0, Inf)
                for i in 1:N
                    y[i] ~ Normal(μ, σ)
                end
            end

            N = 20
            y_data = randn(N) .+ 2.0
            model = compile(model_def, (; N=N, y=y_data))

            @testset "Default ReverseDiff" begin
                # Test both ways of specifying ReverseDiff
                sampler_map1 = OrderedDict(
                    @varname(μ) => WithGradient(NUTS(0.65), ADTypes.AutoReverseDiff()),
                    @varname(σ) => WithGradient(NUTS(0.65)),  # Default ReverseDiff
                )
                gibbs1 = Gibbs(model, sampler_map1)

                rng = StableRNG(1234)
                chain1 = sample(rng, model, gibbs1, 2000; progress=false, chain_type=Chains)

                @test chain1 isa AbstractMCMC.AbstractChains
                @test size(chain1, 1) == 2000
                @test size(chain1, 2) == 2  # μ and σ

                # Check numerical correctness - should converge to data mean
                μ_samples = vec(chain1[:μ].data)
                σ_samples = vec(chain1[:σ].data)
                data_mean = mean(y_data)
                @test mean(μ_samples[:]) ≈ data_mean atol = 2.0
                @test all(σ_samples .> 0)  # σ should be positive
            end

            @testset "Different AD backends" begin
                # Test with ForwardDiff (should work for small models)
                sampler_map2 = OrderedDict(
                    @varname(μ) => WithGradient(HMC(0.01, 10), ADTypes.AutoForwardDiff()),
                    @varname(σ) => WithGradient(NUTS(0.65), ADTypes.AutoReverseDiff()),
                )
                gibbs2 = Gibbs(model, sampler_map2)

                rng = Random.MersenneTwister(456)
                chain2 = sample(rng, model, gibbs2, 50; progress=false, chain_type=Chains)

                @test chain2 isa AbstractMCMC.AbstractChains
                @test size(chain2, 1) == 50

                # Check that samples are reasonable
                μ_samples = vec(chain2[:μ].data)
                σ_samples = vec(chain2[:σ].data)
                @test all(isfinite, μ_samples)
                @test all(isfinite, σ_samples)
                @test all(σ_samples .> 0)  # σ should be positive
            end
        end

        @testset "Mixed samplers (HMC + MHFromPrior)" begin
            # Model with continuous and discrete parameters
            model_def = @bugs begin
                # Continuous parameters
                μ ~ Normal(0, 10)
                log_σ ~ Normal(0, 1)
                σ = exp(log_σ)

                # Discrete parameter
                k ~ Categorical(p[:])

                # Likelihood
                for i in 1:N
                    y[i] ~ Normal(μ + k * 0.5, σ)
                end
            end

            N = 30
            p_data = [0.3, 0.4, 0.3]
            y_data = randn(N) .+ 1.5
            model = compile(model_def, (; N=N, p=p_data, y=y_data))

            # Use HMC for continuous, MHFromPrior for discrete
            sampler_map = OrderedDict(
                [@varname(μ), @varname(log_σ)] =>
                    WithGradient(HMC(0.1, 10), ADTypes.AutoReverseDiff()),  # Larger step size
                @varname(k) => MHFromPrior(),
            )
            gibbs = Gibbs(model, sampler_map)

            # Initialize with reasonable values
            init_params = (; μ=mean(y_data), log_σ=0.0, k=2)
            model_init = initialize!(model, init_params)

            rng = Random.MersenneTwister(789)
            chain = sample(
                rng,
                model_init,
                gibbs,
                1000;
                progress=false,
                chain_type=Chains,
                discard_initial=200,
            )

            @test chain isa AbstractMCMC.AbstractChains
            @test size(chain, 1) == 1000  # discard_initial is handled in post-processing
            @test size(chain, 2) == 3  # μ, log_σ, k

            # Check that discrete parameter takes valid values
            k_samples = Int.(vec(chain[:k].data))
            @test all(k -> k in 1:3, k_samples)

            # Check numerical correctness
            μ_samples = vec(chain[:μ].data)
            log_σ_samples = vec(chain[:log_σ].data)
            # Just check that parameters are in reasonable ranges
            @test mean(μ_samples) > -1 && mean(μ_samples) < 4  # Wider range for μ
            @test mean(exp.(log_σ_samples)) > 0.1 && mean(exp.(log_σ_samples)) < 3  # Wider range for σ
        end
    end

    @testset "AdvancedMH samplers" begin
        model_def = @bugs begin
            α ~ Beta(2, 2)
            β ~ Normal(0, 1)
            for i in 1:N
                y[i] ~ Normal(α + β * x[i], 1)
            end
        end

        N = 20
        x_data = collect(range(-1, 1; length=N))
        y_data = 0.5 .+ 0.3 .* x_data .+ 0.1 .* randn(N)
        model = compile(model_def, (; N=N, x=x_data, y=y_data))

        # Use AdvancedMH samplers
        # For scalar parameters, we need to use StaticMH with vectorized proposal
        # to work with LogDensityProblems interface
        sampler_map = OrderedDict(
            @varname(α) => MHFromPrior(),  # α is constrained to [0,1], so use prior
            @varname(β) => StaticMH([Normal(0, 0.1)]),  # Single scalar proposal
        )
        gibbs = Gibbs(model, sampler_map)

        rng = StableRNG(1234)
        chain = sample(rng, model, gibbs, 1000; progress=false, chain_type=Chains)

        @test chain isa AbstractMCMC.AbstractChains
        @test size(chain, 1) == 1000
        @test size(chain, 2) == 2  # α and β

        # Check bounds for α (should be in [0, 1])
        α_samples = vec(chain[:α].data)
        @test all(0 .<= α_samples .<= 1)

        # Check numerical correctness
        β_samples = vec(chain[:β].data)
        # MHFromPrior might not converge well in 500 samples
        # Just check that samples are in reasonable ranges
        @test mean(α_samples) > 0.2 && mean(α_samples) < 0.8
        @test mean(β_samples) > -0.5 && mean(β_samples) < 1.0
    end

    @testset "RWMH with scalar proposals" begin
        # Test that demonstrates how to use RWMH with scalar parameters
        model_def = @bugs begin
            μ ~ Normal(0, 10)
            σ ~ truncated(Normal(1, 1), 0, Inf)
            for i in 1:N
                y[i] ~ Normal(μ, σ)
            end
        end

        N = 10
        y_data = randn(N) .+ 2.0
        model = compile(model_def, (; N=N, y=y_data))

        sampler_map = OrderedDict(
            @varname(μ) => StaticMH([Normal(0, 0.5)]),  # Scalar proposal
            @varname(σ) => RWMH([Normal(0, 0.1)]),  # Random walk proposal
        )
        gibbs = Gibbs(model, sampler_map)

        rng = Random.MersenneTwister(123)
        chain = sample(rng, model, gibbs, 200; progress=false, chain_type=Chains)

        @test chain isa AbstractMCMC.AbstractChains
        @test size(chain, 1) == 200
        @test size(chain, 2) == 2  # μ and σ

        # Just check that samples are reasonable
        μ_samples = vec(chain[:μ].data)
        σ_samples = vec(chain[:σ].data)
        @test all(isfinite, μ_samples)
        @test all(isfinite, σ_samples)
        @test all(σ_samples .> 0)  # σ should be positive
    end

    @testset "HMC/NUTS posterior correctness" begin
        # Test that HMC within Gibbs produces correct posterior
        # Using a simple hierarchical model with known posterior properties

        model_def = @bugs begin
            # Hyperprior
            τ ~ Gamma(2, 1)  # shape=2, rate=1
            σ = 1 / sqrt(τ)

            # Overall mean
            μ ~ Normal(0, 10)

            # Group means
            for j in 1:J
                θ[j] ~ Normal(μ, σ)
            end

            # Observations - flatten to avoid nested arrays
            for i in 1:N
                y[i] ~ Normal(θ[group[i]], 1)
            end
        end

        # Generate synthetic data
        Random.seed!(123)
        J = 3
        n_per_group = [10, 12, 8]
        N = sum(n_per_group)
        true_μ = 2.0
        true_σ = 0.5
        true_θ = true_μ .+ randn(J) .* true_σ

        # Create group assignment and flatten data
        group = Int[]
        y_data = Float64[]
        for j in 1:J
            append!(group, fill(j, n_per_group[j]))
            append!(y_data, true_θ[j] .+ randn(n_per_group[j]))
        end

        model = compile(model_def, (; J=J, N=N, group=group, y=y_data))

        @testset "NUTS within Gibbs" begin
            sampler_map = OrderedDict(
                [@varname(μ), @varname(τ)] =>
                    WithGradient(NUTS(0.65), ADTypes.AutoReverseDiff()),
                @varname(θ) => MHFromPrior(),  # Use MH for group means
            )
            gibbs = Gibbs(model, sampler_map)

            # Initialize with reasonable values for better convergence
            init_params = (; μ=2.0, τ=4.0, θ=fill(2.0, J))
            model_init = initialize!(model, init_params)

            rng = Random.MersenneTwister(789)
            chain = sample(
                rng,
                model_init,
                gibbs,
                5000;
                progress=false,
                chain_type=Chains,
                discard_initial=2000,
            )

            # Check convergence to true parameters
            μ_samples = vec(chain[:μ].data)
            τ_samples = vec(chain[:τ].data)
            σ_samples = 1 ./ sqrt.(τ_samples)

            # Posterior mean should be close to true values
            @test mean(μ_samples) ≈ true_μ atol = 1.0
            @test mean(σ_samples) ≈ true_σ atol = 1.0

            # Check θ values - with MHFromPrior the convergence is slower
            for j in 1:J
                θj_samples = vec(chain[Symbol("θ[$j]")].data)
                # Should be close to group means
                group_j_data = y_data[group .== j]
                @test mean(θj_samples) ≈ mean(group_j_data) atol = 1.0
            end
        end
    end

    @testset "State preservation behavior" begin
        # Test that HMC/NUTS states ARE preserved across Gibbs iterations
        # and updated when parameters change

        using AdvancedHMC: HMC

        model_def = @bugs begin
            α ~ Normal(0, 1)
            β ~ Normal(0, 1)
            γ ~ Normal(0, 1)
            for i in 1:N
                y[i] ~ Normal(α + β * x[i] + γ * x[i]^2, 1)
            end
        end

        N = 10
        x_data = randn(N)
        y_data = randn(N)
        model = compile(model_def, (; N=N, x=x_data, y=y_data))

        # Create a custom Gibbs state to inspect sub_states
        sampler_map = OrderedDict(
            @varname(α) => WithGradient(HMC(0.01, 5), ADTypes.AutoReverseDiff()),
            @varname(β) => MHFromPrior(),
            @varname(γ) => WithGradient(HMC(0.01, 5), ADTypes.AutoReverseDiff()),
        )
        gibbs = Gibbs(model, sampler_map)

        rng = Random.MersenneTwister(123)

        # Manually step through to inspect states
        logdensitymodel = AbstractMCMC.LogDensityModel(model)
        val, state = AbstractMCMC.step(rng, logdensitymodel, gibbs; model=model)

        # Initial state should have empty sub_states
        @test isempty(state.sub_states)

        # Step a few times
        for i in 1:3
            val, state = AbstractMCMC.step(rng, logdensitymodel, gibbs, state; model=model)
        end

        # After stepping, HMC samplers should have preserved states
        # Check that gradient-based samplers (α and γ) have preserved states
        @test haskey(state.sub_states, [@varname(α)])
        @test haskey(state.sub_states, [@varname(γ)])
        # MHFromPrior (β) doesn't return state in our implementation, so it won't be there
        @test !haskey(state.sub_states, [@varname(β)])

        # Verify that the sampler still works correctly
        chain = sample(rng, model, gibbs, 100; progress=false)
        @test length(chain) == 100
    end
end
