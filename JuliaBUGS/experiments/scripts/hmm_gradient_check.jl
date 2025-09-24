#!/usr/bin/env julia

using Random
using Distributions
using Printf
using ForwardDiff

include(joinpath(@__DIR__, "..", "utils.jl"))

using JuliaBUGS
using JuliaBUGS: @bugs, getparams
JuliaBUGS.@bugs_primitive Categorical Normal exp
using LogDensityProblems

parse_list(str) = begin
    s = strip(str)
    isempty(s) && return Int[]
    all(isdigit, replace(s, "," => "")) && return [parse(Int, s)]
    return parse.(Int, split(s, ","))
end

seeds = let v = get(ENV, "AGC_SWEEP_SEEDS", get(ENV, "AGC_SEED", "1"))
    xs = parse_list(v)
    isempty(xs) ? [1] : xs
end
Ks = let v = get(ENV, "AGC_SWEEP_K", get(ENV, "AGC_K", "2"))
    xs = parse_list(v)
    isempty(xs) ? [2] : xs
end
Ts = let v = get(ENV, "AGC_SWEEP_T", get(ENV, "AGC_T", "50"))
    xs = parse_list(v)
    isempty(xs) ? [50] : xs
end

eps = try parse(Float64, get(ENV, "AGC_EPS", "1e-5")) catch; 1e-5 end
verbose = get(ENV, "AGC_VERBOSE", "0") == "1"
function default_hmm_params(K)
    means_true = collect(range(-1.0, 1.0; length=K))
    sigmas_true = fill(0.6, K)
    return means_true, sigmas_true
end

function simulate_hmm(rng, T, K; init_probs, transition, means, sigmas)
    z = Vector{Int}(undef, T)
    y = Vector{Float64}(undef, T)
    z[1] = rand(rng, Categorical(init_probs))
    y[1] = rand(rng, Normal(means[z[1]], sigmas[z[1]]))
    for t in 2:T
        z[t] = rand(rng, Categorical(transition[z[t - 1], :]))
        y[t] = rand(rng, Normal(means[z[t]], sigmas[z[t]]))
    end
    return (; z, y)
end

function priors_from_truth(means_true, sigmas_true)
    mu_prior_mean = means_true
    mu_prior_std = 1.0
    logsigma_prior_mean = log.(sigmas_true)
    logsigma_prior_std = 0.3
    return mu_prior_mean, mu_prior_std, logsigma_prior_mean, logsigma_prior_std
end

function hmm_param_model()
    @bugs begin
        for k in 1:K
            mu[k] ~ Normal(mu_prior_mean[k], mu_prior_std)
            log_sigma[k] ~ Normal(logsigma_prior_mean[k], logsigma_prior_std)
            sigma[k] = exp(log_sigma[k])
        end

        z[1] ~ Categorical(init_probs)
        y[1] ~ Normal(mu[z[1]], sigma[z[1]])

        for t in 2:T
            z[t] ~ Categorical(transition[z[t - 1], 1:K])
            y[t] ~ Normal(mu[z[t]], sigma[z[t]])
        end
    end
end

function finite_difference(f, x; ϵ=1e-5)
    g = similar(x)
    fx = f(x)
    for i in eachindex(x)
        xi = x[i]
        x[i] = xi + ϵ
        fp = f(x)
        x[i] = xi - ϵ
        fm = f(x)
        x[i] = xi
        g[i] = (fp - fm) / (2ϵ)
    end
    return g, fx
end

function run_case(seed::Int, K::Int, T::Int; ϵ::Float64=1e-5, verbose::Bool=false)
    rng = MersenneTwister(seed)
    init_probs = fill(1.0 / K, K)
    diag = 0.85
    off = (1 - diag) / (K - 1)
    transition = fill(off, K, K)
    for k in 1:K
        transition[k, k] = diag
    end
    means_true, sigmas_true = default_hmm_params(K)
    sim = simulate_hmm(rng, T, K; init_probs=init_probs, transition=transition, means=means_true, sigmas=sigmas_true)

    mu_prior_mean, mu_prior_std, logsigma_prior_mean, logsigma_prior_std = priors_from_truth(means_true, sigmas_true)

    data = (
        T = T,
        K = K,
        y = sim.y,
        init_probs = init_probs,
        transition = transition,
        mu_prior_mean = mu_prior_mean,
        mu_prior_std = mu_prior_std,
        logsigma_prior_mean = logsigma_prior_mean,
        logsigma_prior_std = logsigma_prior_std,
    )

    model, θ0 = compile_autmarg(hmm_param_model(), data)
    target(θ) = Base.invokelatest(LogDensityProblems.logdensity, model, θ)
    autograd = ForwardDiff.gradient(target, θ0)
    fdgrad, logp = finite_difference(target, copy(θ0); ϵ=ϵ)

    diffs = autograd .- fdgrad
    max_abs_diff = maximum(abs, diffs)
    denom = map(i -> max(max(abs(autograd[i]), abs(fdgrad[i])), 1e-12), eachindex(θ0))
    rel_diffs = abs.(diffs) ./ denom
    max_rel_diff = maximum(rel_diffs)

    if verbose
        @printf "# HMM gradient check\n"
        @printf "seed=%d, K=%d, T=%d\n" seed K T
        @printf "logp = %.12f\n" logp
        for i in eachindex(θ0)
            @printf "θ[%d]: autodiff=%.6e fd=%.6e diff=%.2e rel=%.2e\n" i autograd[i] fdgrad[i] diffs[i] rel_diffs[i]
        end
    end

    return logp, max_abs_diff, max_rel_diff
end

# Decide whether this is a sweep or single run
is_single = (length(seeds) == 1) && (length(Ks) == 1) && (length(Ts) == 1)

if !is_single
    @printf "# HMM gradient sweep\n"
    @printf "# seed,K,T,max_abs_diff,max_rel_diff,logp\n"
end

for seed in seeds, K in Ks, T in Ts
    logp, max_abs_diff, max_rel_diff = run_case(seed, K, T; ϵ=eps, verbose=(verbose && is_single))
    if is_single && !verbose
        @printf "# HMM gradient check\n"
        @printf "seed=%d, K=%d, T=%d\n" seed K T
        @printf "logp = %.12f\n" logp
        @printf "max_abs_diff=%.3e, max_rel_diff=%.3e\n" max_abs_diff max_rel_diff
    elseif !is_single
        @printf "%d,%d,%d,%.3e,%.3e,%.12f\n" seed K T max_abs_diff max_rel_diff logp
    end
end
