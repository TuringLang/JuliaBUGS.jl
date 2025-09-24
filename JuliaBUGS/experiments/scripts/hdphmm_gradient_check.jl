#!/usr/bin/env julia

using Random
using Distributions
using Printf
using ForwardDiff

include(joinpath(@__DIR__, "..", "utils.jl"))

using JuliaBUGS
using JuliaBUGS: @bugs

# Deterministic helper to add kappa mass to one index of a vector
function diagshift(alpha_beta::AbstractVector{T}, i::Integer, kappa::Real) where {T}
    K = length(alpha_beta)
    out = Vector{T}(undef, K)
    @inbounds for j in 1:K
        out[j] = alpha_beta[j]
    end
    if 1 <= i <= K
        @inbounds out[i] = out[i] + kappa
    end
    return out
end

# Allow these functions in @bugs
JuliaBUGS.@bugs_primitive Categorical Normal Beta Dirichlet exp diagshift
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

seeds = let v = get(ENV, "AHDPG_SWEEP_SEEDS", get(ENV, "AHDPG_SEED", "1"))
    xs = parse_list(v)
    isempty(xs) ? [1] : xs
end
Ks = let v = get(ENV, "AHDPG_SWEEP_K", get(ENV, "AHDPG_K", "5"))
    xs = parse_list(v)
    isempty(xs) ? [5] : xs
end
Ts = let v = get(ENV, "AHDPG_SWEEP_T", get(ENV, "AHDPG_T", "200"))
    xs = parse_list(v)
    isempty(xs) ? [200] : xs
end

alpha = try parse(Float64, get(ENV, "AHDPG_ALPHA", "5.0")) catch; 5.0 end
gamma = try parse(Float64, get(ENV, "AHDPG_GAMMA", "1.0")) catch; 1.0 end
kappa = try parse(Float64, get(ENV, "AHDPG_KAPPA", "0.0")) catch; 0.0 end

eps = try parse(Float64, get(ENV, "AHDPG_EPS", "1e-5")) catch; 1e-5 end
verbose = get(ENV, "AHDPG_VERBOSE", "0") == "1"

# Emission priors
m0 = try parse(Float64, get(ENV, "AHDPG_MU0", "0.0")) catch; 0.0 end
s0 = try parse(Float64, get(ENV, "AHDPG_MU0_STD", "1.0")) catch; 1.0 end
ℓ0 = try parse(Float64, get(ENV, "AHDPG_LOGSIGMA0", string(log(0.6)))) catch; log(0.6) end
τ0 = try parse(Float64, get(ENV, "AHDPG_LOGSIGMA0_STD", "0.3")) catch; 0.3 end

function stick_break(v::AbstractVector)
    K = length(v) + 1
    beta = similar(v, Float64, K)
    stick = 1.0
    for k in 1:K-1
        beta[k] = v[k] * stick
        stick *= (1 - v[k])
    end
    beta[K] = stick
    return beta
end

function simulate_hdp_params(rng::AbstractRNG, K::Int; α::Real, γ::Real, κ::Real)
    v = [rand(rng, Beta(1.0, γ)) for _ in 1:K-1]
    beta = stick_break(v)
    pi = Array{Float64}(undef, K, K)
    for i in 1:K
        a = α .* beta
        a[i] += κ
        pi[i, :] = rand(rng, Dirichlet(a))
    end
    return beta, pi
end

function simulate_y(rng::AbstractRNG, T::Int, K::Int; rho, pi, mu, sigma)
    z = Vector{Int}(undef, T)
    y = Vector{Float64}(undef, T)
    z[1] = rand(rng, Categorical(rho))
    y[1] = rand(rng, Normal(mu[z[1]], sigma[z[1]]))
    for t in 2:T
        z[t] = rand(rng, Categorical(pi[z[t - 1], :]))
        y[t] = rand(rng, Normal(mu[z[t]], sigma[z[t]]))
    end
    return y
end

function hdphmm_param_model()
    @bugs begin
        # Emissions
        for k in 1:K
            mu[k] ~ Normal(mu0, mu0_std)
            log_sigma[k] ~ Normal(logsigma0, logsigma0_std)
            sigma[k] = exp(log_sigma[k])
        end

        # Stick-breaking weights
        for k in 1:(K - 1)
            v[k] ~ Beta(1.0, gamma)
        end
        # Deterministic stick-breaking to beta without reassigning scalars
        remain[1] = 1.0
        for k in 1:(K - 1)
            beta[k] = v[k] * remain[k]
            remain[k + 1] = remain[k] * (1.0 - v[k])
        end
        beta[K] = remain[K]

        # Transition rows with HDP weak-limit prior + sticky kappa via diagshift
        for j in 1:K
            alpha_beta[j] = alpha * beta[j]
        end
        for i in 1:K
            transition[i, 1:K] ~ Dirichlet(diagshift(alpha_beta[1:K], i, kappa))
        end

        # Initial distribution = beta (standard HDP-HMM choice)
        z[1] ~ Categorical(beta[1:K])
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

function run_case(seed::Int, K::Int, T::Int; α::Float64, γ::Float64, κ::Float64, ϵ::Float64, verbose::Bool)
    rng = MersenneTwister(seed)
    # Simulate from prior for data generation
    mu_true = collect(range(-1.5, 1.5; length=K))
    sigma_true = fill(0.6, K)
    beta_true, pi_true = simulate_hdp_params(rng, K; α=α, γ=γ, κ=κ)
    y = simulate_y(rng, T, K; rho=beta_true, pi=pi_true, mu=mu_true, sigma=sigma_true)

    data = (
        T = T,
        K = K,
        y = y,
        alpha = α,
        gamma = γ,
        kappa = κ,
        mu0 = m0,
        mu0_std = s0,
        logsigma0 = ℓ0,
        logsigma0_std = τ0,
    )

    model, θ0 = compile_autmarg(hdphmm_param_model(), data)
    target(θ) = Base.invokelatest(LogDensityProblems.logdensity, model, θ)
    autograd = ForwardDiff.gradient(target, θ0)
    fdgrad, logp = finite_difference(target, copy(θ0); ϵ=ϵ)

    diffs = autograd .- fdgrad
    max_abs_diff = maximum(abs, diffs)
    denom = map(i -> max(max(abs(autograd[i]), abs(fdgrad[i])), 1e-12), eachindex(θ0))
    rel_diffs = abs.(diffs) ./ denom
    max_rel_diff = maximum(rel_diffs)

    if verbose
        @printf "# HDP-HMM gradient check\n"
        @printf "seed=%d, K=%d, T=%d\n" seed K T
        @printf "logp = %.12f\n" logp
        for i in eachindex(θ0)
            @printf "θ[%d]: autodiff=%.6e fd=%.6e diff=%.2e rel=%.2e\n" i autograd[i] fdgrad[i] diffs[i] rel_diffs[i]
        end
    end

    return logp, max_abs_diff, max_rel_diff
end

is_single = (length(seeds) == 1) && (length(Ks) == 1) && (length(Ts) == 1)

if !is_single
    @printf "# HDP-HMM gradient sweep (sticky κ=%.2f)\n" kappa
    @printf "# seed,K,T,max_abs_diff,max_rel_diff,logp\n"
end

for seed in seeds, K in Ks, T in Ts
    logp, max_abs_diff, max_rel_diff = run_case(seed, K, T; α=alpha, γ=gamma, κ=kappa, ϵ=eps, verbose=(verbose && is_single))
    if is_single && !verbose
        @printf "# HDP-HMM gradient check (sticky κ=%.2f)\n" kappa
        @printf "seed=%d, K=%d, T=%d\n" seed K T
        @printf "logp = %.12f\n" logp
        @printf "max_abs_diff=%.3e, max_rel_diff=%.3e\n" max_abs_diff max_rel_diff
    elseif !is_single
        @printf "%d,%d,%d,%.3e,%.3e,%.12f\n" seed K T max_abs_diff max_rel_diff logp
    end
end
