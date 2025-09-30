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
    if occursin(',', s)
        return parse.(Int, split(s, ","))
    else
        return [parse(Int, s)]
    end
end

seeds = let v = get(ENV, "AGG_SWEEP_SEEDS", get(ENV, "AGG_SEED", "1"))
    xs = parse_list(v)
    isempty(xs) ? [1] : xs
end
Ks = let v = get(ENV, "AGG_SWEEP_K", get(ENV, "AGG_K", "2"))
    xs = parse_list(v)
    isempty(xs) ? [2] : xs
end
Ns = let v = get(ENV, "AGG_SWEEP_N", get(ENV, "AGG_N", "200"))
    xs = parse_list(v)
    isempty(xs) ? [200] : xs
end

eps = try parse(Float64, get(ENV, "AGG_EPS", "1e-5")) catch; 1e-5 end
verbose = get(ENV, "AGG_VERBOSE", "0") == "1"

function simulate_gmm(rng, N, K; weights, means, sigmas)
    z = Vector{Int}(undef, N)
    y = Vector{Float64}(undef, N)
    for i in 1:N
        z[i] = rand(rng, Categorical(weights))
        y[i] = rand(rng, Normal(means[z[i]], sigmas[z[i]]))
    end
    return (; z, y)
end

function default_gmm_params(K)
    weights = fill(1.0 / K, K)
    means_true = collect(range(-1.5, 1.5; length=K))
    sigmas_true = fill(0.7, K)
    return weights, means_true, sigmas_true
end

function priors_from_truth(means_true, sigmas_true)
    mu_prior_mean = means_true
    mu_prior_std = 1.0
    logsigma_prior_mean = log.(sigmas_true)
    logsigma_prior_std = 0.3
    return mu_prior_mean, mu_prior_std, logsigma_prior_mean, logsigma_prior_std
end

function gmm_param_model()
    @bugs begin
        for k in 1:K
            mu[k] ~ Normal(mu_prior_mean[k], mu_prior_std)
            log_sigma[k] ~ Normal(logsigma_prior_mean[k], logsigma_prior_std)
            sigma[k] = exp(log_sigma[k])
        end

        for i in 1:N
            z[i] ~ Categorical(weights)
            y[i] ~ Normal(mu[z[i]], sigma[z[i]])
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

function run_case(seed::Int, K::Int, N::Int; ϵ::Float64=1e-5, verbose::Bool=false)
    rng = MersenneTwister(seed)
    weights, means_true, sigmas_true = default_gmm_params(K)
    sim = simulate_gmm(rng, N, K; weights=weights, means=means_true, sigmas=sigmas_true)

    mu_prior_mean, mu_prior_std, logsigma_prior_mean, logsigma_prior_std = priors_from_truth(means_true, sigmas_true)

    data = (
        N = N,
        K = K,
        y = sim.y,
        weights = weights,
        mu_prior_mean = mu_prior_mean,
        mu_prior_std = mu_prior_std,
        logsigma_prior_mean = logsigma_prior_mean,
        logsigma_prior_std = logsigma_prior_std,
    )

    model, θ0 = compile_autmarg(gmm_param_model(), data)
    target(θ) = Base.invokelatest(LogDensityProblems.logdensity, model, θ)
    autograd = ForwardDiff.gradient(target, θ0)
    fdgrad, logp = finite_difference(target, copy(θ0); ϵ=ϵ)

    diffs = autograd .- fdgrad
    max_abs_diff = maximum(abs, diffs)
    denom = map(i -> max(max(abs(autograd[i]), abs(fdgrad[i])), 1e-12), eachindex(θ0))
    rel_diffs = abs.(diffs) ./ denom
    max_rel_diff = maximum(rel_diffs)

    if verbose
        @printf "# GMM gradient check\n"
        @printf "seed=%d, K=%d, N=%d\n" seed K N
        @printf "logp = %.12f\n" logp
        for i in eachindex(θ0)
            @printf "θ[%d]: autodiff=%.6e fd=%.6e diff=%.2e rel=%.2e\n" i autograd[i] fdgrad[i] diffs[i] rel_diffs[i]
        end
    end

    return logp, max_abs_diff, max_rel_diff
end

is_single = (length(seeds) == 1) && (length(Ks) == 1) && (length(Ns) == 1)

if !is_single
    @printf "# GMM gradient sweep\n"
    @printf "# seed,K,N,max_abs_diff,max_rel_diff,logp\n"
end

for seed in seeds, K in Ks, N in Ns
    logp, max_abs_diff, max_rel_diff = run_case(seed, K, N; ϵ=eps, verbose=(verbose && is_single))
    if is_single && !verbose
        @printf "# GMM gradient check\n"
        @printf "seed=%d, K=%d, N=%d\n" seed K N
        @printf "logp = %.12f\n" logp
        @printf "max_abs_diff=%.3e, max_rel_diff=%.3e\n" max_abs_diff max_rel_diff
    elseif !is_single
        @printf "%d,%d,%d,%.3e,%.3e,%.12f\n" seed K N max_abs_diff max_rel_diff logp
    end
end
