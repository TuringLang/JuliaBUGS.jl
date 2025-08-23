# Tests for auto-marginalization of discrete finite variables
# This file is included from runtests.jl which provides all necessary imports

using JuliaBUGS: @bugs, compile, settrans
using JuliaBUGS.Model: set_evaluation_mode, UseAutoMarginalization, UseGraph

@testset "Auto-Marginalization" begin
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
end
