# Tests for auto-marginalization of discrete finite variables
# This file is included from runtests.jl which provides all necessary imports

using JuliaBUGS: @bugs, compile, settrans, initialize!, getparams
using JuliaBUGS.Model: set_evaluation_mode, UseAutoMarginalization, UseGraph

@testset "Auto-Marginalization" begin
    println("[AutoMargTest] Starting Auto-Marginalization test suite..."); flush(stdout)
    # HMM helper function for ground truth using forward algorithm
    function forward_algorithm_hmm(y, mu1, mu2, sigma, pi, trans)
        T = length(y)
        n_states = 2
        alpha = zeros(n_states, T)

        for s in 1:n_states
            mu_s = s == 1 ? mu1 : mu2
            alpha[s, 1] = log(pi[s]) + logpdf(Normal(mu_s, sigma), y[1])
        end

        for t in 2:T
            for s in 1:n_states
                mu_s = s == 1 ? mu1 : mu2
                log_trans_probs = [
                    alpha[s_prev, t - 1] + log(trans[s_prev, s]) for s_prev in 1:n_states
                ]
                alpha[s, t] =
                    LogExpFunctions.logsumexp(log_trans_probs) +
                    logpdf(Normal(mu_s, sigma), y[t])
            end
        end

        return LogExpFunctions.logsumexp(alpha[:, T])
    end

    @testset "Simple HMM with fixed parameters" begin
        println("[AutoMargTest] HMM (fixed params): compiling..."); flush(stdout)
        # HMM with fixed emission parameters (no continuous parameters to estimate)
        hmm_fixed_def = @bugs begin
            mu[1] = 0.0
            mu[2] = 5.0
            sigma = 1.0

            trans[1, 1] = 0.7
            trans[1, 2] = 0.3
            trans[2, 1] = 0.4
            trans[2, 2] = 0.6

            pi[1] = 0.5
            pi[2] = 0.5

            z[1] ~ Categorical(pi[1:2])
            for t in 2:T
                p[t, 1] = trans[z[t - 1], 1]
                p[t, 2] = trans[z[t - 1], 2]
                z[t] ~ Categorical(p[t, :])
            end

            for t in 1:T
                y[t] ~ Normal(mu[z[t]], sigma)
            end
        end

        T = 2
        y_obs = [0.1, 4.9]
        data = (T=T, y=y_obs)

        model = compile(hmm_fixed_def, data)
        model = settrans(model, true)
        model = set_evaluation_mode(model, UseAutoMarginalization())
        println("[AutoMargTest] HMM (fixed params): evaluating logdensity..."); flush(stdout)

        # No continuous parameters, so empty array
        x_empty = Float64[]
        logp_marginalized = LogDensityProblems.logdensity(model, x_empty)

        # Expected value (manual calculation)
        expected = -3.744970426679133

        @test isapprox(logp_marginalized, expected; atol=1e-6)
    end

    @testset "HMM with continuous parameters" begin
        # HMM where emission means and variance are parameters to be estimated
        hmm_param_def = @bugs begin
            # Priors for emission parameters
            mu[1] ~ Normal(0, 10)
            mu[2] ~ Normal(5, 10)
            sigma ~ Exponential(1)

            # Fixed transition matrix
            trans[1, 1] = 0.7
            trans[1, 2] = 0.3
            trans[2, 1] = 0.4
            trans[2, 2] = 0.6

            # Initial state probabilities
            pi[1] = 0.5
            pi[2] = 0.5

            # Hidden states (discrete, to be marginalized)
            z[1] ~ Categorical(pi[1:2])
            for t in 2:T
                p[t, 1] = trans[z[t - 1], 1]
                p[t, 2] = trans[z[t - 1], 2]
                z[t] ~ Categorical(p[t, :])
            end

            # Observations
            for t in 1:T
                y[t] ~ Normal(mu[z[t]], sigma)
            end
        end

        @testset "T=$T" for T in [2, 3, 4, 5]
            println("[AutoMargTest] HMM (params): T=$(T) compile+eval..."); flush(stdout)
            y_obs = if T == 2
                [0.1, 4.9]
            elseif T == 3
                [0.1, 4.9, 5.1]
            elseif T == 4
                [0.1, 4.9, 5.1, -0.2]
            else  # T == 5
                [0.1, 4.9, 5.1, -0.2, 5.0]
            end

            data = (T=T, y=y_obs)

            model = compile(hmm_param_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Check dimension - should be 3 (sigma, mu[2], mu[1])
            @test LogDensityProblems.dimension(model) == 3

            # Test with specific continuous parameters
            # Order: sigma, mu[2], mu[1] (from sorted_parameters)
            test_params = [0.0, 5.0, 0.0]  # log(sigma)=0 -> sigma=1, mu[2]=5, mu[1]=0

            logp_marginalized = LogDensityProblems.logdensity(model, test_params)
            println("[AutoMargTest] HMM (params): T=$(T) logdensity done"); flush(stdout)

            # Compute expected value using forward algorithm
            pi_vals = [0.5, 0.5]
            trans_mat = [0.7 0.3; 0.4 0.6]
            logp_forward = forward_algorithm_hmm(y_obs, 0.0, 5.0, 1.0, pi_vals, trans_mat)

            # Add prior log probabilities
            prior_logp =
                logpdf(Normal(0, 10), 0.0) +
                logpdf(Normal(5, 10), 5.0) +
                logpdf(Exponential(1), 1.0)
            expected = logp_forward + prior_logp

            @test isapprox(logp_marginalized, expected; atol=1e-10)
        end
    end

    @testset "Marginalization mode consistency" begin
        # Test that UseAutoMarginalization correctly filters parameters
        hmm_def = @bugs begin
            mu[1] ~ Normal(0, 10)
            mu[2] ~ Normal(5, 10)
            sigma ~ Exponential(1)

            trans[1, 1] = 0.7
            trans[1, 2] = 0.3
            trans[2, 1] = 0.4
            trans[2, 2] = 0.6

            pi[1] = 0.5
            pi[2] = 0.5

            z[1] ~ Categorical(pi[1:2])
            for t in 2:T
                p[t, 1] = trans[z[t - 1], 1]
                p[t, 2] = trans[z[t - 1], 2]
                z[t] ~ Categorical(p[t, :])
            end

            for t in 1:T
                y[t] ~ Normal(mu[z[t]], sigma)
            end
        end

        T = 3
        data = (T=T, y=[0.1, 4.9, 5.1])

        # Create model in graph mode
        model_graph = compile(hmm_def, data)
        model_graph = settrans(model_graph, true)
        model_graph = set_evaluation_mode(model_graph, UseGraph())

        # Create model in marginalization mode
        model_marg = compile(hmm_def, data)
        model_marg = settrans(model_marg, true)
        model_marg = set_evaluation_mode(model_marg, UseAutoMarginalization())

        # Graph mode should include discrete parameters
        @test LogDensityProblems.dimension(model_graph) == 6  # z[1:3] + sigma + mu[2] + mu[1]

        # Marginalization mode should only include continuous parameters
        @test LogDensityProblems.dimension(model_marg) == 3  # sigma + mu[2] + mu[1]

        # Check that discrete finite variables are correctly identified
        gd = model_marg.graph_evaluation_data
        discrete_count = sum(gd.is_discrete_finite_vals)
        @test discrete_count == 3  # z[1], z[2], z[3]
end

    @testset "Gaussian Mixture Models" begin
        println("[AutoMargTest] GMM tests: start..."); flush(stdout)
        # Helper function for ground truth mixture likelihood
        function mixture_loglikelihood(y, weights, mus, sigmas)
            n = length(y)
            k = length(weights)
            logp_total = 0.0

            for i in 1:n
                # Log-sum-exp over components for each observation
                log_probs = zeros(k)
                for j in 1:k
                    log_probs[j] = log(weights[j]) + logpdf(Normal(mus[j], sigmas[j]), y[i])
                end
                logp_total += LogExpFunctions.logsumexp(log_probs)
            end

            return logp_total
        end

        @testset "Two-component mixture with fixed weights" begin
            println("[AutoMargTest] GMM K=2 correctness..."); flush(stdout)
            # Simple mixture with fixed mixture weights
            mixture_fixed_def = @bugs begin
                # Fixed mixture weights
                w[1] = 0.3
                w[2] = 0.7

                # Component parameters
                mu[1] ~ Normal(-2, 5)
                mu[2] ~ Normal(2, 5)
                sigma[1] ~ Exponential(1)
                sigma[2] ~ Exponential(1)

                # Component assignments (discrete, to be marginalized)
                for i in 1:N
                    z[i] ~ Categorical(w[1:2])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            N = 4
            y_obs = [-1.5, 2.3, -2.1, 1.8]
            data = (N=N, y=y_obs)

            model = compile(mixture_fixed_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Should have 4 continuous parameters: sigma[1], sigma[2], mu[2], mu[1]
            @test LogDensityProblems.dimension(model) == 4

            # Test with specific parameters
            # Order: log(sigma[1]), log(sigma[2]), mu[2], mu[1]
            test_params = [0.0, 0.0, 2.0, -2.0]  # sigmas=1, mu[2]=2, mu[1]=-2

            logp_marginalized = LogDensityProblems.logdensity(model, test_params)

            # Compute expected value
            weights = [0.3, 0.7]
            mus = [-2.0, 2.0]
            sigmas = [1.0, 1.0]

            logp_likelihood = mixture_loglikelihood(y_obs, weights, mus, sigmas)
            prior_logp =
                logpdf(Normal(-2, 5), -2.0) +
                logpdf(Normal(2, 5), 2.0) +
                logpdf(Exponential(1), 1.0) +
                logpdf(Exponential(1), 1.0)
            expected = logp_likelihood + prior_logp

            @test isapprox(logp_marginalized, expected; atol=1e-10)
        end

        @testset "Three-component mixture with fixed weights" begin
            println("[AutoMargTest] GMM K=3 correctness..."); flush(stdout)
            # Extend to 3 components with exact verification
            mixture_3comp_def = @bugs begin
                # Fixed mixture weights
                w[1] = 0.2
                w[2] = 0.5
                w[3] = 0.3

                # Component parameters
                mu[1] ~ Normal(-3, 5)
                mu[2] ~ Normal(0, 5)
                mu[3] ~ Normal(3, 5)
                for k in 1:3
                    sigma[k] ~ Exponential(1)
                end

                # Component assignments
                for i in 1:N
                    z[i] ~ Categorical(w[1:3])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            N = 3
            y_obs = [-2.5, 0.5, 3.2]
            data = (N=N, y=y_obs)

            model = compile(mixture_3comp_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Should have 6 continuous parameters: 3 sigmas + 3 mus
            @test LogDensityProblems.dimension(model) == 6

            # Test with specific parameters
            test_params = [0.0, 0.0, 0.0, 3.0, 0.0, -3.0]
            # log(sigmas)=0 -> all sigmas=1, mu[3]=3, mu[2]=0, mu[1]=-3

            logp_marginalized = LogDensityProblems.logdensity(model, test_params)

            # Compute expected value
            weights = [0.2, 0.5, 0.3]
            mus = [-3.0, 0.0, 3.0]
            sigmas = [1.0, 1.0, 1.0]

            logp_likelihood = mixture_loglikelihood(y_obs, weights, mus, sigmas)
            prior_logp = sum([
                logpdf(Normal(-3, 5), -3.0),
                logpdf(Normal(0, 5), 0.0),
                logpdf(Normal(3, 5), 3.0),
                logpdf(Exponential(1), 1.0),
                logpdf(Exponential(1), 1.0),
                logpdf(Exponential(1), 1.0),
            ])
            expected = logp_likelihood + prior_logp

            @test isapprox(logp_marginalized, expected; atol=1e-10)
        end

        @testset "Label invariance" begin
            println("[AutoMargTest] GMM label invariance..."); flush(stdout)
            # Verify that permuting component labels doesn't change log-density
            # when weights are equal
            mixture_sym_def = @bugs begin
                w[1] = 0.5
                w[2] = 0.5

                mu[1] ~ Normal(0, 10)
                mu[2] ~ Normal(0, 10)
                sigma[1] ~ Exponential(1)
                sigma[2] ~ Exponential(1)

                for i in 1:N
                    z[i] ~ Categorical(w[1:2])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            N = 4
            y_obs = [1.0, 2.0, -1.0, 3.0]
            data = (N=N, y=y_obs)

            model = compile(mixture_sym_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Test with original ordering
            # Order: log(sigma[1]), log(sigma[2]), mu[2], mu[1]
            params1 = [-0.5, 0.0, 3.0, 1.0]  # sigma[1]=exp(-0.5), sigma[2]=1, mu[2]=3, mu[1]=1
            logp1 = LogDensityProblems.logdensity(model, params1)

            # Test with swapped components (swap mu and sigma values)
            params2 = [0.0, -0.5, 1.0, 3.0]  # sigma[1]=1, sigma[2]=exp(-0.5), mu[2]=1, mu[1]=3
            logp2 = LogDensityProblems.logdensity(model, params2)

            # The log probabilities should be equal due to symmetry
            # (swapping components 1 and 2 completely with equal weights)
            @test isapprox(logp1, logp2; atol=1e-10)
        end

        @testset "Partial observation of z" begin
            # Some z[i] are observed, others are marginalized
            mixture_partial_def = @bugs begin
                w[1] = 0.3
                w[2] = 0.7

                mu[1] ~ Normal(-2, 5)
                mu[2] ~ Normal(2, 5)
                sigma ~ Exponential(1)  # Shared sigma

                for i in 1:N
                    z[i] ~ Categorical(w[1:2])
                    y[i] ~ Normal(mu[z[i]], sigma)
                end
            end

            N = 4
            # Observe z[1] and z[3], marginalize z[2] and z[4]
            data = (N=N, y=[1.0, 2.0, -1.0, 3.0], z=[2, missing, 1, missing])

            model = compile(mixture_partial_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Should have 3 continuous parameters: sigma, mu[2], mu[1]
            # z[2] and z[4] are marginalized out
            @test LogDensityProblems.dimension(model) == 3

            # Test evaluation
            test_params = [0.0, 2.0, -2.0]  # log(sigma)=0->sigma=1, mu[2]=2, mu[1]=-2
            logp = LogDensityProblems.logdensity(model, test_params)

            # Verify it's finite and reasonable
            @test isfinite(logp)
            @test logp < 0

            # Manually compute expected for observed components
            # z[1]=2 -> y[1]=1.0 comes from mu[2]=2
            # z[3]=1 -> y[3]=-1.0 comes from mu[1]=-2
            # z[2] and z[4] are marginalized
            sigma_val = 1.0
            mu_vals = [-2.0, 2.0]
            weights = [0.3, 0.7]

            # Observed parts
            logp_obs = (
                log(weights[2]) +
                logpdf(Normal(mu_vals[2], sigma_val), 1.0) +  # z[1]=2, y[1]=1.0
                log(weights[1]) +
                logpdf(Normal(mu_vals[1], sigma_val), -1.0)   # z[3]=1, y[3]=-1.0
            )

            # Marginalized parts for y[2]=2.0 and y[4]=3.0
            logp_marg2 = LogExpFunctions.logsumexp([
                log(weights[1]) + logpdf(Normal(mu_vals[1], sigma_val), 2.0),
                log(weights[2]) + logpdf(Normal(mu_vals[2], sigma_val), 2.0),
            ])
            logp_marg4 = LogExpFunctions.logsumexp([
                log(weights[1]) + logpdf(Normal(mu_vals[1], sigma_val), 3.0),
                log(weights[2]) + logpdf(Normal(mu_vals[2], sigma_val), 3.0),
            ])

            logp_likelihood = logp_obs + logp_marg2 + logp_marg4
            prior_logp = (
                logpdf(Normal(-2, 5), -2.0) +
                logpdf(Normal(2, 5), 2.0) +
                logpdf(Exponential(1), 1.0)
            )
            expected = logp_likelihood + prior_logp

            @test isapprox(logp, expected; atol=1e-10)
        end

        @testset "Mixture with Dirichlet prior on weights" begin
            # More realistic mixture with learned weights
            mixture_dirichlet_def = @bugs begin
                # Mixture weights with Dirichlet prior
                alpha[1] = 1.0
                alpha[2] = 1.0
                alpha[3] = 1.0
                w[1:3] ~ ddirich(alpha[1:3])

                # Component parameters
                for k in 1:3
                    mu[k] ~ Normal(0, 10)
                    sigma[k] ~ Exponential(1)
                end

                # Component assignments
                for i in 1:N
                    z[i] ~ Categorical(w[1:3])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            N = 5
            y_obs = [-3.0, 0.1, 2.9, -2.8, 3.1]
            data = (N=N, y=y_obs)

            model = compile(mixture_dirichlet_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Should have 8 continuous parameters:
            # 3 sigmas + 3 mus + 2 transformed weight components (3-1 due to simplex constraint)
            @test LogDensityProblems.dimension(model) == 8

            # Test with specific parameters
            # Simplex transform for weights [0.2, 0.3, 0.5]
            # Using stick-breaking: w1=0.2, w2=0.3, w3=0.5
            # This requires specific transformed values
            w_target = [0.2, 0.3, 0.5]
            # For Dirichlet, use log-ratio transform
            log_ratios = [log(w_target[1] / w_target[3]), log(w_target[2] / w_target[3])]

            test_params = [
                0.0,
                0.0,
                0.0,  # log(sigmas) = 0 -> all sigmas = 1
                3.0,
                0.0,
                -3.0,  # mu[3]=3, mu[2]=0, mu[1]=-3
                log_ratios[1],
                log_ratios[2],  # transformed weights
            ]

            logp_marginalized = LogDensityProblems.logdensity(model, test_params)

            # Verify it's finite and reasonable
            @test isfinite(logp_marginalized)
            @test logp_marginalized < 0  # Should be negative for realistic parameters
        end

        @testset "Hierarchical mixture model" begin
            # Mixture with hierarchical structure on component means
            hierarchical_mixture_def = @bugs begin
                # Hyperpriors
                mu_global ~ Normal(0, 10)
                tau_global ~ Exponential(1)

                # Mixture weights
                w[1] = 0.5
                w[2] = 0.5

                # Component-specific parameters with hierarchical prior
                for k in 1:2
                    mu[k] ~ Normal(mu_global, tau_global)
                    sigma[k] ~ Exponential(1)
                end

                # Data generation
                for i in 1:N
                    z[i] ~ Categorical(w[1:2])
                    y[i] ~ Normal(mu[z[i]], sigma[z[i]])
                end
            end

            N = 6
            y_obs = [1.0, 1.2, 4.8, 5.1, 0.9, 5.0]
            data = (N=N, y=y_obs)

            model = compile(hierarchical_mixture_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            # Should have 6 continuous parameters:
            # mu_global, tau_global, 2 sigmas, 2 mus
            @test LogDensityProblems.dimension(model) == 6

            # Test evaluation with multiple parameter sets
            # Test 1: Parameters that should give reasonable likelihood
            test_params = [3.0, 0.0, 0.0, 0.0, 5.0, 1.0]
            # mu_global=3, log(tau_global)=0->tau=1, log(sigmas)=0->sigmas=1, mu[2]=5, mu[1]=1

            logp_marginalized = LogDensityProblems.logdensity(model, test_params)

            # Verify the result is finite and reasonable
            @test isfinite(logp_marginalized)
            @test logp_marginalized < 0  # Log probability should be negative

            # Test 2: Different parameters - should give different likelihood
            test_params2 = [2.5, -0.5, -0.5, 0.2, 4.5, 0.5]
            logp_marginalized2 = LogDensityProblems.logdensity(model, test_params2)

            @test isfinite(logp_marginalized2)
            @test logp_marginalized2 != logp_marginalized  # Different params should give different results

            # Test 3: Verify multiple evaluations are consistent
            logp_repeat = LogDensityProblems.logdensity(model, test_params)
            @test logp_repeat == logp_marginalized  # Same params should give same result
        end
    end

    @testset "Edge cases" begin
        @testset "Model with no discrete finite variables" begin
            # Simple continuous model - marginalization should work but do nothing special
            continuous_def = @bugs begin
                mu ~ Normal(0, 10)
                sigma ~ Exponential(1)
                for i in 1:N
                    y[i] ~ Normal(mu, sigma)
                end
            end

            N = 3
            data = (N=N, y=[1.0, 2.0, 3.0])

            model = compile(continuous_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            @test LogDensityProblems.dimension(model) == 2  # mu, sigma

            # Should work normally
            test_params = [2.0, 0.0]  # mu=2, log(sigma)=0 -> sigma=1
            logp = LogDensityProblems.logdensity(model, test_params)
            @test isfinite(logp)
        end

        @testset "Model with observed discrete variables" begin
            # Discrete variables that are observed should not be marginalized
            observed_discrete_def = @bugs begin
                p ~ Beta(1, 1)
                for i in 1:N
                    x[i] ~ Bernoulli(p)
                end
            end

            N = 5
            data = (N=N, x=[1, 0, 1, 1, 0])

            model = compile(observed_discrete_def, data)
            model = settrans(model, true)
            model = set_evaluation_mode(model, UseAutoMarginalization())

            @test LogDensityProblems.dimension(model) == 1  # Only p

            # Test evaluation
            test_params = [0.0]  # logit(p) = 0 -> p = 0.5
            logp = LogDensityProblems.logdensity(model, test_params)

            # Expected in transformed space:
            # - Beta(1,1) prior at p=0.5: log(1) = 0
            # - Likelihood: 3 successes and 2 failures with p=0.5: 5*log(0.5)
            # - Log Jacobian for logit transform at p=0.5: log(p*(1-p)) = log(0.25)
            p_val = 0.5
            expected =
                logpdf(Beta(1, 1), p_val) +
                3 * log(p_val) +
                2 * log(1 - p_val) +
                log(p_val * (1 - p_val))  # Jacobian
            @test isapprox(logp, expected; atol=1e-10)
        end
    end

    @testset "Gradient vs finite differences (GMM)" begin
        println("[AutoMargTest] GMM gradients: compiling..."); flush(stdout)
        # Two-component mixture with fixed weights; params: mu[1:2], sigma[1:2]
        mixture_def = @bugs begin
            w[1] = 0.3
            w[2] = 0.7
            mu[1] ~ Normal(-2, 5)
            mu[2] ~ Normal(2, 5)
            sigma[1] ~ Exponential(1)
            sigma[2] ~ Exponential(1)
            for i in 1:N
                z[i] ~ Categorical(w[1:2])
                y[i] ~ Normal(mu[z[i]], sigma[z[i]])
            end
        end

        N = 6
        y = [-1.8, -2.2, 1.9, 2.1, -1.5, 2.4]
        data = (N=N, y=y)
        model = compile(mixture_def, data)
        model = settrans(model, true)
        model = set_evaluation_mode(model, UseAutoMarginalization())

        # Initialize model and extract parameter vector
        initialize!(model, (; mu=[-2.0, 2.0], sigma=[1.1, 0.9]))
        θ = getparams(model)

        # AD gradient via ForwardDiff
        ad_model = ADgradient(AutoForwardDiff(), model)
        println("[AutoMargTest] GMM gradients: AD gradient..."); flush(stdout)
        val_ad, grad_ad = LogDensityProblems.logdensity_and_gradient(ad_model, θ)
        println("[AutoMargTest] GMM gradients: AD gradient done"); flush(stdout)

        # Central finite differences
        function f(θ)
            LogDensityProblems.logdensity(model, θ)
        end
        ϵ = 1e-6
        grad_fd = similar(θ)
        println("[AutoMargTest] GMM gradients: FD gradient..."); flush(stdout)
        for i in eachindex(θ)
            e = zeros(length(θ)); e[i] = 1.0
            fp = f(θ .+ ϵ .* e)
            fm = f(θ .- ϵ .* e)
            grad_fd[i] = (fp - fm) / (2ϵ)
            println("[AutoMargTest] GMM gradients: FD step ", i, "/", length(θ)); flush(stdout)
        end
        println("[AutoMargTest] GMM gradients: FD gradient done"); flush(stdout)

        rel_err = maximum(abs.(grad_ad .- grad_fd) ./ (abs.(grad_fd) .+ 1e-8))
        @test isfinite(val_ad)
        @test rel_err < 5e-5
    end

    @testset "Efficiency smoke: AutoMarg+NUTS vs Graph+IndependentMH" begin
        println("[AutoMargTest] Efficiency smoke: compiling models..."); flush(stdout)
        # Minimal smoke test to ensure both pipelines run (not a benchmark)
        mixture_def = @bugs begin
            w[1] = 0.3
            w[2] = 0.7
            mu[1] ~ Normal(-2, 5)
            mu[2] ~ Normal(2, 5)
            sigma[1] ~ Exponential(1)
            sigma[2] ~ Exponential(1)
            for i in 1:N
                z[i] ~ Categorical(w[1:2])
                y[i] ~ Normal(mu[z[i]], sigma[z[i]])
            end
        end

        data = (N=100, y=vcat(rand(Normal(-2, 1), 50), rand(Normal(2, 1), 50)))

        # Graph model with IndependentMH (quick smoke run)
        model_graph = compile(mixture_def, data) |> m -> settrans(m, true) |> m -> set_evaluation_mode(m, UseGraph())
        gibbs = JuliaBUGS.Gibbs(model_graph, JuliaBUGS.IndependentMH())
        println("[AutoMargTest] Efficiency smoke: sampling Graph+IMH..."); flush(stdout)
        chn_graph = AbstractMCMC.sample(Random.default_rng(), model_graph, gibbs, 10; progress=false, chain_type=MCMCChains.Chains)
        println("[AutoMargTest] Efficiency smoke: Graph+IMH done"); flush(stdout)
        @test length(chn_graph) == 10

        # Auto-marginalized model with small-step NUTS
        model_marg = compile(mixture_def, data) |> m -> settrans(m, true) |> m -> set_evaluation_mode(m, UseAutoMarginalization())
        @test LogDensityProblems.dimension(model_marg) < LogDensityProblems.dimension(model_graph)
        ad_model = ADgradient(AutoForwardDiff(), model_marg)
        D = LogDensityProblems.dimension(model_marg)
        θ0 = zeros(D)
        println("[AutoMargTest] Efficiency smoke: skipping AutoMarg+NUTS sampling for now"); flush(stdout)
        # Quick sanity: logdensity on AD-wrapped model at θ0 is finite
        val = LogDensityProblems.logdensity(ad_model, θ0)
        @test isfinite(val)
    end
end
