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

function simulate_hmm(rng::AbstractRNG, T::Int, K::Int; init_probs, transition, means, sigmas)
    states = Vector{Int}(undef, T)
    obs = Vector{Float64}(undef, T)

    states[1] = rand(rng, Categorical(init_probs))
    obs[1] = rand(rng, Normal(means[states[1]], sigmas[states[1]]))

    for t in 2:T
        prev = states[t - 1]
        states[t] = rand(rng, Categorical(transition[prev, :]))
        obs[t] = rand(rng, Normal(means[states[t]], sigmas[states[t]]))
    end

    return (; states, obs)
end

function forward_logp(obs, init_probs, transition, means, sigmas)
    T = length(obs)
    K = length(init_probs)

    log_emissions = Array{Float64}(undef, T, K)
    for t in 1:T, k in 1:K
        log_emissions[t, k] = logpdf(Normal(means[k], sigmas[k]), obs[t])
    end

    log_transition = log.(transition)
    log_alpha = Vector{Float64}(undef, K)
    for k in 1:K
        log_alpha[k] = log(init_probs[k]) + log_emissions[1, k]
    end

    tmp = similar(log_alpha)
    for t in 2:T
        for k in 1:K
            tmp[k] = log_emissions[t, k] + logsumexp(log_alpha .+ log_transition[:, k])
        end
        log_alpha, tmp = tmp, log_alpha
    end

    return logsumexp(log_alpha)
end

function build_hmm_model()
    @bugs begin
        z[1] ~ Categorical(init_probs)
        y[1] ~ Normal(means[z[1]], sigmas[z[1]])

        for t in 2:T
            z[t] ~ Categorical(transition[z[t - 1], 1:K])
            y[t] ~ Normal(means[z[t]], sigmas[z[t]])
        end
    end
end

function default_params(K)
    init_probs = fill(1.0 / K, K)
    diag = 0.85
    off = (1.0 - diag) / (K - 1)
    transition = fill(off, K, K)
    for k in 1:K
        transition[k, k] = diag
    end
    means = collect(range(-1.5, 1.5; length=K))
    sigmas = fill(0.6, K)
    return init_probs, transition, means, sigmas
end

function run_case(; K::Int, T::Int, seed::Int)
    rng = MersenneTwister(seed)
    init_probs, transition, means, sigmas = default_params(K)
    sim = simulate_hmm(rng, T, K; init_probs=init_probs, transition=transition, means=means, sigmas=sigmas)

    model_def = build_hmm_model()
    data = (
        T = T,
        K = K,
        y = sim.obs,
        init_probs = init_probs,
        transition = transition,
        means = means,
        sigmas = sigmas,
    )

    model, θ0 = compile_autmarg(model_def, data)
    logp = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)
    logp_ref = forward_logp(sim.obs, init_probs, transition, means, sigmas)
    return logp, logp_ref
end

seed_str = strip(get(ENV, "AM_SWEEP_SEEDS", "1"))
seed_vals = isempty(seed_str) ? [1] : parse.(Int, split(seed_str, ','))
K_str = strip(get(ENV, "AM_SWEEP_K", "2,4"))
Ks = parse.(Int, split(K_str, ','))
T_str = strip(get(ENV, "AM_SWEEP_T", "50,200"))
Ts = parse.(Int, split(T_str, ','))

@printf "# HMM correctness sweep\n"
@printf "# seed,K,T,logp_autmarg,logp_forward,diff\n"
for seed in seed_vals, K in Ks, T in Ts
    logp, logp_ref = run_case(K=K, T=T, seed=seed)
    diff = logp - logp_ref
    @printf "%d,%d,%d,%.12f,%.12f,%.3e\n" seed K T logp logp_ref diff
end
