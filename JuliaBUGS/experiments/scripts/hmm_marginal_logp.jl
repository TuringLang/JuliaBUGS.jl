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

function simulate_hmm(rng::AbstractRNG, T::Int; init_probs, transition, means, sigmas)
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

function forward_logp(obs::AbstractVector, init_probs, transition, means, sigmas)
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

rng = MersenneTwister(get(ENV, "AM_SEED", "1") |> x -> parse(Int, x))
T = get(ENV, "AM_T", "50") |> x -> parse(Int, x)
K = 2
init_probs = [0.6, 0.4]
transition = [0.95 0.05; 0.10 0.90]
means = [-1.0, 1.5]
sigmas = fill(0.4, K)

sim = simulate_hmm(rng, T; init_probs=init_probs, transition=transition, means=means, sigmas=sigmas)

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
diff = logp - logp_ref

@printf "Marginalized log probability (T=%d): %.6f\n" T logp
@printf "Forward reference log probability: %.6f (Δ = %.2e)\n" logp_ref diff
