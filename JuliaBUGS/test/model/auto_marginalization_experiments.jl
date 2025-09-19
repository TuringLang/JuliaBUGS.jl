# Comprehensive Experiments for Auto-Marginalization Validation
# This file contains experiments to validate the correctness and performance
# of the auto-marginalization implementation in JuliaBUGS.

using Test
using JuliaBUGS
using JuliaBUGS: @bugs, compile, settrans, initialize!, getparams
using JuliaBUGS.Model: set_evaluation_mode, UseAutoMarginalization, UseGraph
using LogDensityProblems
using AbstractMCMC
using AdvancedHMC
using MCMCChains
using Distributions
using LogExpFunctions
using LinearAlgebra
using Random
using Statistics
using BenchmarkTools
using ForwardDiff

# Set random seed for reproducibility
Random.seed!(42)

@testset "Auto-Marginalization Validation Experiments" begin

    # ================================================================================
    # SECTION 1: CORRECTNESS VALIDATION
    # ================================================================================

    @testset "1. Correctness Validation" begin

        @testset "1.1 Simple Binary Models" begin
            println("Testing simple binary discrete models...")

            # Test 1: Single Bernoulli with Normal emission
            model1 = @bugs begin
                z ~ Bernoulli(0.4)
                mu = z ? 5.0 : 0.0
                y ~ Normal(mu, 1.0)
            end

            data1 = (y=2.5,)
            compiled1 = compile(model1, data1)
            compiled1 = settrans(compiled1, true)

            # Compare UseGraph vs UseAutoMarginalization
            graph_model = set_evaluation_mode(compiled1, UseGraph())
            marg_model = set_evaluation_mode(compiled1, UseAutoMarginalization())

            # For graph model, need to sum over z
            logp_graph_z0 = LogDensityProblems.logdensity(graph_model, [0.0])  # z=0
            logp_graph_z1 = LogDensityProblems.logdensity(graph_model, [1.0])  # z=1
            logp_graph_marginal = LogExpFunctions.logsumexp([logp_graph_z0, logp_graph_z1])

            # Auto-marginalization should give same result
            logp_marg = LogDensityProblems.logdensity(marg_model, Float64[])

            @test isapprox(logp_marg, logp_graph_marginal; rtol=1e-10)

            # Test 2: Chain of Bernoullis
            model2 = @bugs begin
                z1 ~ Bernoulli(0.3)
                p2 = z1 ? 0.8 : 0.2
                z2 ~ Bernoulli(p2)
                mu = z2 ? 10.0 : -5.0
                y ~ Normal(mu, 2.0)
            end

            data2 = (y=3.0,)
            compiled2 = compile(model2, data2)
            compiled2 = settrans(compiled2, true)
            marg_model2 = set_evaluation_mode(compiled2, UseAutoMarginalization())

            # Manual calculation
            p_z1_0 = 0.7
            p_z1_1 = 0.3
            p_z2_0_given_z1_0 = 0.8
            p_z2_1_given_z1_0 = 0.2
            p_z2_0_given_z1_1 = 0.2
            p_z2_1_given_z1_1 = 0.8

            # P(y=3) marginalizing over z1 and z2
            p_y = p_z1_0 * p_z2_0_given_z1_0 * pdf(Normal(-5.0, 2.0), 3.0) +
                  p_z1_0 * p_z2_1_given_z1_0 * pdf(Normal(10.0, 2.0), 3.0) +
                  p_z1_1 * p_z2_0_given_z1_1 * pdf(Normal(-5.0, 2.0), 3.0) +
                  p_z1_1 * p_z2_1_given_z1_1 * pdf(Normal(10.0, 2.0), 3.0)

            expected_logp = log(p_y)
            actual_logp = LogDensityProblems.logdensity(marg_model2, Float64[])

            @test isapprox(actual_logp, expected_logp; rtol=1e-10)
        end

        @testset "1.2 Categorical Variables" begin
            println("Testing categorical discrete variables...")

            # Test 3: Simple 3-state categorical
            model3 = @bugs begin
                pi = [0.2, 0.3, 0.5]
                z ~ Categorical(pi)
                mu = [0.0, 5.0, 10.0]
                y ~ Normal(mu[z], 1.0)
            end

            data3 = (y=4.5,)
            compiled3 = compile(model3, data3)
            compiled3 = settrans(compiled3, true)
            marg_model3 = set_evaluation_mode(compiled3, UseAutoMarginalization())

            # Manual calculation
            pi_vals = [0.2, 0.3, 0.5]
            mu_vals = [0.0, 5.0, 10.0]
            sigma = 1.0
            y_obs = 4.5

            p_y = sum(pi_vals[i] * pdf(Normal(mu_vals[i], sigma), y_obs) for i in 1:3)
            expected_logp = log(p_y)
            actual_logp = LogDensityProblems.logdensity(marg_model3, Float64[])

            @test isapprox(actual_logp, expected_logp; rtol=1e-10)
        end

        @testset "1.3 Mixed Continuous-Discrete Models" begin
            println("Testing models with both continuous and discrete variables...")

            # Test 4: Mixture model with continuous parameters
            model4 = @bugs begin
                # Continuous parameters
                mu1 ~ Normal(0, 10)
                mu2 ~ Normal(5, 10)
                sigma ~ Exponential(1)

                # Fixed mixture weights
                w = [0.4, 0.6]

                # Discrete assignments and observations
                for i in 1:N
                    z[i] ~ Categorical(w)
                    mu = z[i] == 1 ? mu1 : mu2
                    y[i] ~ Normal(mu, sigma)
                end
            end

            N = 3
            y_obs = [-1.0, 4.0, 5.5]
            data4 = (N=N, y=y_obs)

            compiled4 = compile(model4, data4)
            compiled4 = settrans(compiled4, true)
            marg_model4 = set_evaluation_mode(compiled4, UseAutoMarginalization())

            # Check dimension (should be 3: mu1, mu2, sigma)
            @test LogDensityProblems.dimension(marg_model4) == 3

            # Test with specific parameters
            test_params = [0.0, 5.0, 0.0]  # mu1=0, mu2=5, log(sigma)=0 -> sigma=1
            logp = LogDensityProblems.logdensity(marg_model4, test_params)

            # Manual calculation
            w_vals = [0.4, 0.6]
            mu_vals = [0.0, 5.0]
            sigma_val = 1.0

            logp_likelihood = 0.0
            for y in y_obs
                p = sum(w_vals[k] * pdf(Normal(mu_vals[k], sigma_val), y) for k in 1:2)
                logp_likelihood += log(p)
            end

            logp_prior = logpdf(Normal(0, 10), 0.0) +
                        logpdf(Normal(5, 10), 5.0) +
                        logpdf(Exponential(1), 1.0)

            expected_logp = logp_likelihood + logp_prior

            @test isapprox(logp, expected_logp; rtol=1e-10)
        end
    end

    # ================================================================================
    # SECTION 2: GRADIENT CORRECTNESS
    # ================================================================================

    @testset "2. Gradient Correctness" begin
        println("Testing gradient computation correctness...")

        @testset "2.1 Finite Difference Validation" begin
            # Create a model with discrete marginalization
            grad_model = @bugs begin
                # Parameters
                mu1 ~ Normal(-2, 5)
                mu2 ~ Normal(2, 5)
                sigma1 ~ Exponential(1)
                sigma2 ~ Exponential(1)

                w = [0.3, 0.7]

                for i in 1:N
                    z[i] ~ Categorical(w)
                    mu = z[i] == 1 ? mu1 : mu2
                    sig = z[i] == 1 ? sigma1 : sigma2
                    y[i] ~ Normal(mu, sig)
                end
            end

            N = 5
            y_obs = [-1.5, 2.0, -2.1, 1.8, 2.5]
            data = (N=N, y=y_obs)

            compiled = compile(grad_model, data)
            compiled = settrans(compiled, true)
            marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

            # Initialize and get parameters
            initialize!(marg_model, (; mu1=-2.0, mu2=2.0, sigma1=1.0, sigma2=1.0))
            θ = getparams(marg_model)

            # Compute AD gradient
            ad_model = ADgradient(AutoForwardDiff(), marg_model)
            val_ad, grad_ad = LogDensityProblems.logdensity_and_gradient(ad_model, θ)

            # Compute finite difference gradient
            ϵ = 1e-6
            grad_fd = similar(θ)
            for i in eachindex(θ)
                θ_plus = copy(θ)
                θ_minus = copy(θ)
                θ_plus[i] += ϵ
                θ_minus[i] -= ϵ

                lp_plus = LogDensityProblems.logdensity(marg_model, θ_plus)
                lp_minus = LogDensityProblems.logdensity(marg_model, θ_minus)

                grad_fd[i] = (lp_plus - lp_minus) / (2ϵ)
            end

            # Check relative error
            rel_error = maximum(abs.(grad_ad .- grad_fd) ./ (abs.(grad_fd) .+ 1e-8))
            @test rel_error < 1e-5

            println("  Maximum relative gradient error: $rel_error")
        end

        @testset "2.2 Gradient Consistency" begin
            # Test that multiple gradient evaluations give consistent results
            grad_model = @bugs begin
                p ~ Beta(2, 3)
                for i in 1:N
                    z[i] ~ Bernoulli(p)
                    mu = z[i] ? 3.0 : -1.0
                    y[i] ~ Normal(mu, 1.0)
                end
            end

            N = 4
            y_obs = [-0.5, 2.8, -1.2, 3.1]
            data = (N=N, y=y_obs)

            compiled = compile(grad_model, data)
            compiled = settrans(compiled, true)
            marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

            ad_model = ADgradient(AutoForwardDiff(), marg_model)

            # Test at multiple points
            test_points = [[-0.5], [0.0], [0.5]]

            for θ in test_points
                val1, grad1 = LogDensityProblems.logdensity_and_gradient(ad_model, θ)
                val2, grad2 = LogDensityProblems.logdensity_and_gradient(ad_model, θ)

                @test val1 == val2
                @test all(grad1 .== grad2)
            end
        end
    end

    # ================================================================================
    # SECTION 3: PERFORMANCE BENCHMARKING
    # ================================================================================

    @testset "3. Performance Benchmarking" begin
        println("Running performance benchmarks...")

        @testset "3.1 HMM Scaling" begin
            println("  Testing HMM performance scaling with sequence length...")

            hmm_def = @bugs begin
                # Fixed parameters for benchmarking
                mu1 = 0.0
                mu2 = 5.0
                sigma = 1.0

                trans = [0.7 0.3; 0.4 0.6]
                pi = [0.5, 0.5]

                z[1] ~ Categorical(pi)
                for t in 2:T
                    p = trans[z[t-1], :]
                    z[t] ~ Categorical(p)
                end

                for t in 1:T
                    mu = z[t] == 1 ? mu1 : mu2
                    y[t] ~ Normal(mu, sigma)
                end
            end

            # Test different sequence lengths
            T_values = [5, 10, 20, 40]
            times_graph = Float64[]
            times_marg = Float64[]

            for T in T_values
                println("    T = $T")

                # Generate synthetic data
                y_obs = vcat(
                    randn(div(T, 2)) .* 1.0 .+ 0.0,  # From state 1
                    randn(T - div(T, 2)) .* 1.0 .+ 5.0  # From state 2
                )
                data = (T=T, y=y_obs)

                # Graph model
                model_graph = compile(hmm_def, data)
                model_graph = settrans(model_graph, true)
                model_graph = set_evaluation_mode(model_graph, UseGraph())

                # Time graph model (average over z configurations)
                t_graph = @elapsed begin
                    for _ in 1:10
                        z_config = rand(0:1, T)
                        params = vcat(z_config)
                        LogDensityProblems.logdensity(model_graph, params)
                    end
                end
                push!(times_graph, t_graph / 10)

                # Auto-marginalization model
                model_marg = compile(hmm_def, data)
                model_marg = settrans(model_marg, true)
                model_marg = set_evaluation_mode(model_marg, UseAutoMarginalization())

                # Time marginalized model
                t_marg = @elapsed begin
                    for _ in 1:10
                        LogDensityProblems.logdensity(model_marg, Float64[])
                    end
                end
                push!(times_marg, t_marg / 10)
            end

            println("    Graph times: ", times_graph)
            println("    Marg times:  ", times_marg)
            println("    Speedup factors: ", times_graph ./ times_marg)

            # Check that marginalization doesn't blow up exponentially
            @test maximum(times_marg) < 1.0  # Should stay under 1 second even for T=40
        end

        @testset "3.2 Mixture Model Scaling" begin
            println("  Testing mixture model performance with number of components...")

            mixture_def = @bugs begin
                # Parameters
                for k in 1:K
                    mu[k] ~ Normal(0, 10)
                    sigma[k] ~ Exponential(1)
                end

                # Equal weights
                for k in 1:K
                    w[k] = 1.0 / K
                end

                # Data
                for i in 1:N
                    z[i] ~ Categorical(w[1:K])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            # Test different numbers of components
            K_values = [2, 3, 4]
            N = 20

            for K in K_values
                println("    K = $K components")

                # Generate synthetic mixture data
                y_obs = Float64[]
                for k in 1:K
                    append!(y_obs, randn(div(N, K)) .+ k * 3.0)
                end

                data = (K=K, N=length(y_obs), y=y_obs)

                model = compile(mixture_def, data)
                model = settrans(model, true)
                model_marg = set_evaluation_mode(model, UseAutoMarginalization())

                # Check dimension
                expected_dim = 2 * K  # K means + K sigmas
                @test LogDensityProblems.dimension(model_marg) == expected_dim

                # Benchmark
                test_params = zeros(expected_dim)

                t = @elapsed begin
                    for _ in 1:100
                        LogDensityProblems.logdensity(model_marg, test_params)
                    end
                end

                println("      Time per evaluation: $(t/100 * 1000) ms")

                # Should remain tractable
                @test t/100 < 0.1  # Less than 100ms per evaluation
            end
        end
    end

    # ================================================================================
    # SECTION 4: COMPARISON WITH MANUAL MARGINALIZATION
    # ================================================================================

    @testset "4. Manual vs Auto Marginalization Comparison" begin
        println("Comparing auto-marginalization with manual implementation...")

        @testset "4.1 Simple HMM Comparison" begin
            # Manual forward algorithm implementation
            function manual_hmm_logp(y_obs, mu1, mu2, sigma, pi, trans)
                T = length(y_obs)

                # Forward pass
                alpha = zeros(2, T)

                # Initialize
                alpha[1, 1] = log(pi[1]) + logpdf(Normal(mu1, sigma), y_obs[1])
                alpha[2, 1] = log(pi[2]) + logpdf(Normal(mu2, sigma), y_obs[1])

                # Recurse
                for t in 2:T
                    for j in 1:2
                        mu_j = j == 1 ? mu1 : mu2
                        trans_probs = [alpha[i, t-1] + log(trans[i, j]) for i in 1:2]
                        alpha[j, t] = LogExpFunctions.logsumexp(trans_probs) +
                                     logpdf(Normal(mu_j, sigma), y_obs[t])
                    end
                end

                return LogExpFunctions.logsumexp(alpha[:, T])
            end

            # Auto-marginalized model
            hmm_model = @bugs begin
                mu1 ~ Normal(0, 10)
                mu2 ~ Normal(5, 10)
                sigma ~ Exponential(1)

                trans = [0.7 0.3; 0.4 0.6]
                pi = [0.5, 0.5]

                z[1] ~ Categorical(pi)
                for t in 2:T
                    p = trans[z[t-1], :]
                    z[t] ~ Categorical(p)
                end

                for t in 1:T
                    mu = z[t] == 1 ? mu1 : mu2
                    y[t] ~ Normal(mu, sigma)
                end
            end

            T = 10
            y_obs = vcat(randn(5) .* 1.0, randn(5) .* 1.0 .+ 5.0)
            data = (T=T, y=y_obs)

            model = compile(hmm_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            # Test at specific parameter values
            mu1_val = 0.0
            mu2_val = 5.0
            sigma_val = 1.0

            # Parameters in transformed space: log(sigma), mu2, mu1
            test_params = [0.0, mu2_val, mu1_val]

            # Auto-marginalized log probability
            auto_logp = LogDensityProblems.logdensity(model_marg, test_params)

            # Manual calculation
            pi_vals = [0.5, 0.5]
            trans_mat = [0.7 0.3; 0.4 0.6]
            manual_likelihood = manual_hmm_logp(y_obs, mu1_val, mu2_val, sigma_val,
                                               pi_vals, trans_mat)

            # Add priors
            prior_logp = logpdf(Normal(0, 10), mu1_val) +
                        logpdf(Normal(5, 10), mu2_val) +
                        logpdf(Exponential(1), sigma_val)

            manual_logp = manual_likelihood + prior_logp

            @test isapprox(auto_logp, manual_logp; rtol=1e-10)

            println("  Auto-marginalized logp: $auto_logp")
            println("  Manual logp: $manual_logp")
            println("  Difference: $(abs(auto_logp - manual_logp))")
        end

        @testset "4.2 Mixture Model Comparison" begin
            # Manual mixture likelihood
            function manual_mixture_logp(y_obs, weights, mus, sigmas)
                logp = 0.0
                for y in y_obs
                    p = sum(weights[k] * pdf(Normal(mus[k], sigmas[k]), y)
                           for k in 1:length(weights))
                    logp += log(p)
                end
                return logp
            end

            # Auto-marginalized mixture model
            mix_model = @bugs begin
                mu1 ~ Normal(-2, 5)
                mu2 ~ Normal(2, 5)
                mu3 ~ Normal(0, 5)
                sigma ~ Exponential(1)

                w = [0.3, 0.5, 0.2]

                for i in 1:N
                    z[i] ~ Categorical(w)
                    mu = z[i] == 1 ? mu1 : (z[i] == 2 ? mu2 : mu3)
                    y[i] ~ Normal(mu, sigma)
                end
            end

            N = 15
            y_obs = vcat(
                randn(5) .- 2.0,  # Component 1
                randn(7) .+ 2.0,  # Component 2
                randn(3) .+ 0.0   # Component 3
            )
            shuffle!(y_obs)

            data = (N=N, y=y_obs)

            model = compile(mix_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            # Test parameters
            mu_vals = [-2.0, 2.0, 0.0]
            sigma_val = 1.0
            weights = [0.3, 0.5, 0.2]

            # Parameters in transformed space: log(sigma), mu3, mu2, mu1
            test_params = [0.0, mu_vals[3], mu_vals[2], mu_vals[1]]

            # Auto-marginalized log probability
            auto_logp = LogDensityProblems.logdensity(model_marg, test_params)

            # Manual calculation
            manual_likelihood = manual_mixture_logp(y_obs, weights, mu_vals,
                                                   [sigma_val, sigma_val, sigma_val])

            # Add priors
            prior_logp = sum([
                logpdf(Normal(-2, 5), mu_vals[1]),
                logpdf(Normal(2, 5), mu_vals[2]),
                logpdf(Normal(0, 5), mu_vals[3]),
                logpdf(Exponential(1), sigma_val)
            ])

            manual_logp = manual_likelihood + prior_logp

            @test isapprox(auto_logp, manual_logp; rtol=1e-10)

            println("  Auto-marginalized logp: $auto_logp")
            println("  Manual logp: $manual_logp")
            println("  Difference: $(abs(auto_logp - manual_logp))")
        end
    end

    # ================================================================================
    # SECTION 5: SAMPLING VALIDATION
    # ================================================================================

    @testset "5. Sampling Validation" begin
        println("Validating sampling with auto-marginalization...")

        @testset "5.1 NUTS Sampling" begin
            # Simple mixture for sampling test
            sample_model = @bugs begin
                mu1 ~ Normal(-2, 2)
                mu2 ~ Normal(2, 2)
                sigma ~ Exponential(1)

                w = [0.4, 0.6]

                for i in 1:N
                    z[i] ~ Categorical(w)
                    mu = z[i] == 1 ? mu1 : mu2
                    y[i] ~ Normal(mu, sigma)
                end
            end

            # Generate data from known parameters
            true_mu1 = -2.0
            true_mu2 = 2.0
            true_sigma = 1.0

            N = 50
            n1 = 20  # 40% from component 1
            n2 = 30  # 60% from component 2

            y_obs = vcat(
                randn(n1) .* true_sigma .+ true_mu1,
                randn(n2) .* true_sigma .+ true_mu2
            )
            shuffle!(y_obs)

            data = (N=N, y=y_obs)

            model = compile(sample_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            # Wrap with AD for gradient-based sampling
            ad_model = ADgradient(AutoForwardDiff(), model_marg)

            # Initialize near true values
            D = LogDensityProblems.dimension(model_marg)
            θ0 = zeros(D)  # Reasonable starting point in transformed space

            # Run NUTS sampling
            samples = AbstractMCMC.sample(
                Random.default_rng(),
                ad_model,
                NUTS(0.65),
                100;  # Small number for testing
                progress=false,
                n_adapts=50,
                init_params=θ0,
                discard_initial=0
            )

            # Extract samples
            sample_array = reduce(hcat, samples.z.θ)

            # Check convergence (very rough check for test)
            # Parameters are: log(sigma), mu2, mu1
            mean_params = mean(sample_array, dims=2)

            # Transform back
            sigma_est = exp(mean_params[1])
            mu2_est = mean_params[2]
            mu1_est = mean_params[3]

            println("  True values: mu1=$true_mu1, mu2=$true_mu2, sigma=$true_sigma")
            println("  Estimates:   mu1=$mu1_est, mu2=$mu2_est, sigma=$sigma_est")

            # Very loose bounds for testing (proper convergence needs more samples)
            @test abs(mu1_est - true_mu1) < 1.0
            @test abs(mu2_est - true_mu2) < 1.0
            @test abs(sigma_est - true_sigma) < 0.5
        end
    end

    # ================================================================================
    # SECTION 6: EDGE CASES AND STRESS TESTS
    # ================================================================================

    @testset "6. Edge Cases and Stress Tests" begin
        println("Testing edge cases and stress scenarios...")

        @testset "6.1 Deep Dependency Chains" begin
            # Model with deep chain of discrete dependencies
            deep_model = @bugs begin
                p1 = 0.4
                z1 ~ Bernoulli(p1)

                p2 = z1 ? 0.7 : 0.3
                z2 ~ Bernoulli(p2)

                p3 = z2 ? 0.8 : 0.2
                z3 ~ Bernoulli(p3)

                p4 = z3 ? 0.6 : 0.4
                z4 ~ Bernoulli(p4)

                mu = z4 ? 10.0 : -10.0
                y ~ Normal(mu, 1.0)
            end

            data = (y=5.0,)
            model = compile(deep_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            # Should handle deep chains without issues
            logp = LogDensityProblems.logdensity(model_marg, Float64[])
            @test isfinite(logp)

            println("  Deep chain model log probability: $logp")
        end

        @testset "6.2 Large State Spaces" begin
            # Model with many discrete states
            large_state_model = @bugs begin
                K = 10  # 10 states

                # Uniform prior over states
                for k in 1:K
                    w[k] = 1.0 / K
                end

                # Simple emissions
                for i in 1:N
                    z[i] ~ Categorical(w[1:K])
                    mu = z[i] * 2.0  # Different mean for each state
                    y[i] ~ Normal(mu, 1.0)
                end
            end

            N = 5
            y_obs = [2.1, 4.2, 6.1, 8.3, 10.2]
            data = (N=N, y=y_obs)

            model = compile(large_state_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            # Should handle 10^5 = 100,000 total configurations
            logp = LogDensityProblems.logdensity(model_marg, Float64[])
            @test isfinite(logp)

            println("  Large state space model log probability: $logp")
        end

        @testset "6.3 Mixed Observed/Unobserved Discrete" begin
            # Some discrete variables observed, others marginalized
            mixed_obs_model = @bugs begin
                p = 0.5

                # z1 and z3 will be observed, z2 and z4 marginalized
                z1 ~ Bernoulli(p)
                z2 ~ Bernoulli(p)
                z3 ~ Bernoulli(p)
                z4 ~ Bernoulli(p)

                sum_z = z1 + z2 + z3 + z4
                y ~ Normal(sum_z, 1.0)
            end

            data = (z1=1, z3=0, y=2.0)  # z2 and z4 are missing

            model = compile(mixed_obs_model, data)
            model = settrans(model, true)
            model_marg = set_evaluation_mode(model, UseAutoMarginalization())

            logp = LogDensityProblems.logdensity(model_marg, Float64[])

            # Manual calculation: z1=1, z3=0, so sum needs z2+z4=1
            # This happens when (z2=0,z4=1) or (z2=1,z4=0)
            p_val = 0.5
            p_sum = 2 * p_val * (1 - p_val)  # Two ways to get sum=1
            expected_logp = log(p_val) + log(1 - p_val) + log(p_sum) +
                           logpdf(Normal(2.0, 1.0), 2.0)

            @test isapprox(logp, expected_logp; rtol=1e-10)
        end
    end

    println("\n" * "="^80)
    println("AUTO-MARGINALIZATION VALIDATION COMPLETE")
    println("="^80)
end

println("\nRunning auto-marginalization experiments...")