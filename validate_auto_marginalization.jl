#!/usr/bin/env julia

# Standalone validation script for auto-marginalization
# This script validates the auto-marginalization implementation against
# manual calculations and known ground truth values.

println("=" * "^" * "80")
println("AUTO-MARGINALIZATION VALIDATION SCRIPT")
println("=" * "^" * "80")
println()

# Check if we can load JuliaBUGS
try
    using Pkg
    Pkg.activate("JuliaBUGS")
    using JuliaBUGS
    using Distributions
    using LogExpFunctions
    using LogDensityProblems
    using LinearAlgebra
    using Random

    println("✓ Successfully loaded JuliaBUGS and dependencies")
    println()
catch e
    println("ERROR: Could not load JuliaBUGS. Make sure you're in the right directory.")
    println("Error details: ", e)
    exit(1)
end

using JuliaBUGS: @bugs, compile, settrans
using JuliaBUGS.Model: set_evaluation_mode, UseAutoMarginalization, UseGraph

# Set random seed for reproducibility
Random.seed!(42)

# Test counter
test_passed = 0
test_failed = 0

function run_test(name, test_fn)
    global test_passed, test_failed
    print("Testing $name... ")
    try
        test_fn()
        println("✓ PASSED")
        test_passed += 1
    catch e
        println("✗ FAILED")
        println("  Error: ", e)
        test_failed += 1
    end
end

# ============================================================================
# TEST 1: Simple Bernoulli-Normal Model
# ============================================================================

function test_simple_bernoulli()
    model = @bugs begin
        z ~ Bernoulli(0.4)
        mu = z ? 5.0 : 0.0
        y ~ Normal(mu, 1.0)
    end

    data = (y=2.5,)
    compiled = compile(model, data)
    compiled = settrans(compiled, true)

    # Auto-marginalization
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())
    logp_marg = LogDensityProblems.logdensity(marg_model, Float64[])

    # Manual calculation
    p_z0 = 0.6
    p_z1 = 0.4
    p_y_given_z0 = pdf(Normal(0.0, 1.0), 2.5)
    p_y_given_z1 = pdf(Normal(5.0, 1.0), 2.5)
    expected = log(p_z0 * p_y_given_z0 + p_z1 * p_y_given_z1)

    if !isapprox(logp_marg, expected; rtol=1e-10)
        throw("Log probabilities don't match: got $logp_marg, expected $expected")
    end
end

run_test("Simple Bernoulli-Normal", test_simple_bernoulli)

# ============================================================================
# TEST 2: Categorical with 3 States
# ============================================================================

function test_categorical()
    model = @bugs begin
        pi = [0.2, 0.3, 0.5]
        z ~ Categorical(pi)
        mu = [0.0, 5.0, 10.0]
        y ~ Normal(mu[z], 1.0)
    end

    data = (y=4.5,)
    compiled = compile(model, data)
    compiled = settrans(compiled, true)
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

    logp_marg = LogDensityProblems.logdensity(marg_model, Float64[])

    # Manual calculation
    pi_vals = [0.2, 0.3, 0.5]
    mu_vals = [0.0, 5.0, 10.0]
    p_y = sum(pi_vals[i] * pdf(Normal(mu_vals[i], 1.0), 4.5) for i in 1:3)
    expected = log(p_y)

    if !isapprox(logp_marg, expected; rtol=1e-10)
        throw("Log probabilities don't match: got $logp_marg, expected $expected")
    end
end

run_test("3-state Categorical", test_categorical)

# ============================================================================
# TEST 3: Two-Component Mixture Model
# ============================================================================

function test_mixture_model()
    model = @bugs begin
        mu1 ~ Normal(-2, 5)
        mu2 ~ Normal(2, 5)
        sigma ~ Exponential(1)

        w = [0.4, 0.6]

        for i in 1:N
            z[i] ~ Categorical(w)
            mu = z[i] == 1 ? mu1 : mu2
            y[i] ~ Normal(mu, sigma)
        end
    end

    N = 3
    y_obs = [-1.0, 4.0, 0.0]
    data = (N=N, y=y_obs)

    compiled = compile(model, data)
    compiled = settrans(compiled, true)
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

    # Test with specific parameters
    test_params = [0.0, 2.0, -2.0]  # log(sigma)=0 -> sigma=1, mu2=2, mu1=-2
    logp = LogDensityProblems.logdensity(marg_model, test_params)

    # Manual calculation
    w_vals = [0.4, 0.6]
    mu_vals = [-2.0, 2.0]
    sigma_val = 1.0

    logp_likelihood = 0.0
    for y in y_obs
        p = sum(w_vals[k] * pdf(Normal(mu_vals[k], sigma_val), y) for k in 1:2)
        logp_likelihood += log(p)
    end

    logp_prior = logpdf(Normal(-2, 5), -2.0) +
                 logpdf(Normal(2, 5), 2.0) +
                 logpdf(Exponential(1), 1.0)

    expected = logp_likelihood + logp_prior

    if !isapprox(logp, expected; rtol=1e-10)
        throw("Log probabilities don't match: got $logp, expected $expected")
    end
end

run_test("Two-component Mixture", test_mixture_model)

# ============================================================================
# TEST 4: Simple HMM
# ============================================================================

function test_simple_hmm()
    model = @bugs begin
        # Fixed parameters
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

    T = 3
    y_obs = [0.1, 4.9, 5.1]
    data = (T=T, y=y_obs)

    compiled = compile(model, data)
    compiled = settrans(compiled, true)
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

    logp = LogDensityProblems.logdensity(marg_model, Float64[])

    # Manual forward algorithm
    function forward_alg()
        alpha = zeros(2, T)

        # Initialize
        alpha[1, 1] = log(0.5) + logpdf(Normal(0.0, 1.0), y_obs[1])
        alpha[2, 1] = log(0.5) + logpdf(Normal(5.0, 1.0), y_obs[1])

        # Recurse
        trans_mat = [0.7 0.3; 0.4 0.6]
        for t in 2:T
            for j in 1:2
                mu_j = j == 1 ? 0.0 : 5.0
                trans_probs = [alpha[i, t-1] + log(trans_mat[i, j]) for i in 1:2]
                alpha[j, t] = LogExpFunctions.logsumexp(trans_probs) +
                             logpdf(Normal(mu_j, 1.0), y_obs[t])
            end
        end

        return LogExpFunctions.logsumexp(alpha[:, T])
    end

    expected = forward_alg()

    if !isapprox(logp, expected; rtol=1e-10)
        throw("Log probabilities don't match: got $logp, expected $expected")
    end
end

run_test("Simple HMM (T=3)", test_simple_hmm)

# ============================================================================
# TEST 5: Chain of Dependencies
# ============================================================================

function test_dependency_chain()
    model = @bugs begin
        z1 ~ Bernoulli(0.3)
        p2 = z1 ? 0.8 : 0.2
        z2 ~ Bernoulli(p2)
        mu = z2 ? 10.0 : -5.0
        y ~ Normal(mu, 2.0)
    end

    data = (y=3.0,)
    compiled = compile(model, data)
    compiled = settrans(compiled, true)
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())

    logp = LogDensityProblems.logdensity(marg_model, Float64[])

    # Manual calculation
    p_z1_0 = 0.7
    p_z1_1 = 0.3
    p_z2_0_given_z1_0 = 0.8
    p_z2_1_given_z1_0 = 0.2
    p_z2_0_given_z1_1 = 0.2
    p_z2_1_given_z1_1 = 0.8

    p_y = p_z1_0 * p_z2_0_given_z1_0 * pdf(Normal(-5.0, 2.0), 3.0) +
          p_z1_0 * p_z2_1_given_z1_0 * pdf(Normal(10.0, 2.0), 3.0) +
          p_z1_1 * p_z2_0_given_z1_1 * pdf(Normal(-5.0, 2.0), 3.0) +
          p_z1_1 * p_z2_1_given_z1_1 * pdf(Normal(10.0, 2.0), 3.0)

    expected = log(p_y)

    if !isapprox(logp, expected; rtol=1e-10)
        throw("Log probabilities don't match: got $logp, expected $expected")
    end
end

run_test("Dependency Chain", test_dependency_chain)

# ============================================================================
# TEST 6: Dimension Check
# ============================================================================

function test_dimension_reduction()
    model = @bugs begin
        # Continuous parameters
        mu1 ~ Normal(0, 10)
        mu2 ~ Normal(5, 10)
        sigma ~ Exponential(1)

        # Discrete variables (3 of them)
        for i in 1:3
            z[i] ~ Bernoulli(0.5)
            mu = z[i] ? mu2 : mu1
            y[i] ~ Normal(mu, sigma)
        end
    end

    data = (y=[0.1, 4.9, 0.2])

    # Graph model includes discrete parameters
    compiled = compile(model, data)
    compiled = settrans(compiled, true)
    graph_model = set_evaluation_mode(compiled, UseGraph())
    dim_graph = LogDensityProblems.dimension(graph_model)

    # Marginalized model excludes discrete parameters
    marg_model = set_evaluation_mode(compiled, UseAutoMarginalization())
    dim_marg = LogDensityProblems.dimension(marg_model)

    # Graph should have 3 continuous + 3 discrete = 6 parameters
    # Marginalized should have only 3 continuous parameters
    if dim_graph != 6 || dim_marg != 3
        throw("Dimension mismatch: graph=$dim_graph (expected 6), marginalized=$dim_marg (expected 3)")
    end
end

run_test("Dimension Reduction", test_dimension_reduction)

# ============================================================================
# SUMMARY
# ============================================================================

println()
println("=" * "^" * "80")
println("VALIDATION SUMMARY")
println("=" * "^" * "80")
println("Tests passed: $test_passed")
println("Tests failed: $test_failed")

if test_failed == 0
    println()
    println("✅ All validation tests passed successfully!")
    println("The auto-marginalization implementation appears to be working correctly.")
else
    println()
    println("⚠️  Some tests failed. Please review the errors above.")
end

println()
println("Note: This is a basic validation script. For comprehensive testing,")
println("run the full test suite with more samples and benchmarks.")