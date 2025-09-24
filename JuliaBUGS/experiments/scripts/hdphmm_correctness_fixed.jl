#!/usr/bin/env julia

using Random
using Distributions
using Printf

include(joinpath(@__DIR__, "..", "utils.jl"))

using JuliaBUGS
using JuliaBUGS: @bugs
JuliaBUGS.@bugs_primitive Categorical Normal
using LogDensityProblems
using LogExpFunctions: logsumexp

parse_list(str) = begin
    s = strip(str)
    isempty(s) && return Int[]
    if occursin(',', s)
        return parse.(Int, split(s, ","))
    else
        return [parse(Int, s)]
    end
end

seeds = let v = get(ENV, "AHDPC_SEEDS", "1")
    xs = parse_list(v)
    isempty(xs) ? [1] : xs
end
Ks = let v = get(ENV, "AHDPC_K", "5,10")
    xs = parse_list(v)
    isempty(xs) ? [5, 10] : xs
end
Ts = let v = get(ENV, "AHDPC_T", "100,200")
    xs = parse_list(v)
    isempty(xs) ? [100, 200] : xs
end

alpha = try parse(Float64, get(ENV, "AHDPC_ALPHA", "5.0")) catch; 5.0 end
gamma = try parse(Float64, get(ENV, "AHDPC_GAMMA", "1.0")) catch; 1.0 end
kappa = try parse(Float64, get(ENV, "AHDPC_KAPPA", "0.0")) catch; 0.0 end

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

function simulate_hmm(rng::AbstractRNG, T::Int, K::Int; rho, pi, means, sigmas)
    z = Vector{Int}(undef, T)
    y = Vector{Float64}(undef, T)
    z[1] = rand(rng, Categorical(rho))
    y[1] = rand(rng, Normal(means[z[1]], sigmas[z[1]]))
    for t in 2:T
        z[t] = rand(rng, Categorical(pi[z[t - 1], :]))
        y[t] = rand(rng, Normal(means[z[t]], sigmas[z[t]]))
    end
    return (; z, y)
end

function default_emission_params(K)
    means = collect(range(-1.5, 1.5; length=K))
    sigmas = fill(0.6, K)
    return means, sigmas
end

function forward_logp(obs, rho, pi, means, sigmas)
    T = length(obs)
    K = length(rho)
    log_emissions = Array{Float64}(undef, T, K)
    for t in 1:T, k in 1:K
        log_emissions[t, k] = logpdf(Normal(means[k], sigmas[k]), obs[t])
    end
    log_pi = log.(pi)
    log_alpha = Vector{Float64}(undef, K)
    for k in 1:K
        log_alpha[k] = log(rho[k]) + log_emissions[1, k]
    end
    tmp = similar(log_alpha)
    for t in 2:T
        for k in 1:K
            tmp[k] = log_emissions[t, k] + logsumexp(log_alpha .+ log_pi[:, k])
        end
        log_alpha, tmp = tmp, log_alpha
    end
    return logsumexp(log_alpha)
end

function build_model()
    @bugs begin
        z[1] ~ Categorical(init_probs)
        y[1] ~ Normal(means[z[1]], sigmas[z[1]])
        for t in 2:T
            z[t] ~ Categorical(transition[z[t - 1], 1:K])
            y[t] ~ Normal(means[z[t]], sigmas[z[t]])
        end
    end
end

function run_case(; K::Int, T::Int, seed::Int, α::Float64, γ::Float64, κ::Float64)
    rng = MersenneTwister(seed)
    beta, pi = simulate_hdp_params(rng, K; α=α, γ=γ, κ=κ)
    means, sigmas = default_emission_params(K)
    sim = simulate_hmm(rng, T, K; rho=beta, pi=pi, means=means, sigmas=sigmas)

    model_def = build_model()
    data = (
        T = T,
        K = K,
        y = sim.y,
        init_probs = beta,
        transition = pi,
        means = means,
        sigmas = sigmas,
    )
    model, θ0 = compile_autmarg(model_def, data)
    logp = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)
    logp_ref = forward_logp(sim.y, beta, pi, means, sigmas)
    return logp, logp_ref
end

@printf "# HDP-HMM correctness (fixed params, sticky κ=%.2f)\n" kappa
@printf "# seed,K,T,alpha,gamma,logp_autmarg,logp_forward,diff\n"
for seed in seeds, K in Ks, T in Ts
    logp, logp_ref = run_case(K=K, T=T, seed=seed, α=alpha, γ=gamma, κ=kappa)
    diff = logp - logp_ref
    @printf "%d,%d,%d,%.3f,%.3f,%.12f,%.12f,%.3e\n" seed K T alpha gamma logp logp_ref diff
end

