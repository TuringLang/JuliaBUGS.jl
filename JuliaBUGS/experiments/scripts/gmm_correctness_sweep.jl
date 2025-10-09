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

function simulate_gmm(rng::AbstractRNG, N::Int, K::Int; weights, means, sigmas)
    z = Vector{Int}(undef, N)
    y = Vector{Float64}(undef, N)
    for i in 1:N
        z[i] = rand(rng, Categorical(weights))
        y[i] = rand(rng, Normal(means[z[i]], sigmas[z[i]]))
    end
    return (; z, y)
end

function closed_form_logp(y, weights, means, sigmas)
    N = length(y)
    K = length(weights)
    log_weights = log.(weights)
    logvals = zeros(N)
    for i in 1:N
        comps = similar(log_weights)
        for k in 1:K
            comps[k] = log_weights[k] + logpdf(Normal(means[k], sigmas[k]), y[i])
        end
        logvals[i] = logsumexp(comps)
    end
    return sum(logvals)
end

function build_gmm_model(N, K)
    @bugs begin
        for i in 1:N
            z[i] ~ Categorical(weights)
            y[i] ~ Normal(means[z[i]], sigmas[z[i]])
        end
    end
end

function default_params(K)
    weights = fill(1.0 / K, K)
    means = collect(range(-2.0, 2.0; length=K))
    sigmas = fill(0.9, K)
    return weights, means, sigmas
end

function run_case(; K::Int, N::Int, seed::Int)
    rng = MersenneTwister(seed)
    weights, means, sigmas = default_params(K)
    sim = simulate_gmm(rng, N, K; weights=weights, means=means, sigmas=sigmas)

    model_def = build_gmm_model(N, K)
    data = (
        N = N,
        K = K,
        y = sim.y,
        weights = weights,
        means = means,
        sigmas = sigmas,
    )

    model, θ0 = compile_autmarg(model_def, data)
    logp = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)
    logp_ref = closed_form_logp(sim.y, weights, means, sigmas)
    return logp, logp_ref
end

seed_str = strip(get(ENV, "AG_SWEEP_SEEDS", "1"))
seed_vals = isempty(seed_str) ? [1] : parse.(Int, split(seed_str, ','))
K_str = strip(get(ENV, "AG_SWEEP_K", "2,4"))
Ks = parse.(Int, split(K_str, ','))
N_str = strip(get(ENV, "AG_SWEEP_N", "100,1000"))
Ns = parse.(Int, split(N_str, ','))

@printf "# GMM correctness sweep\n"
@printf "# seed,K,N,logp_autmarg,logp_closed_form,diff\n"
for seed in seed_vals, K in Ks, N in Ns
    logp, logp_ref = run_case(K=K, N=N, seed=seed)
    diff = logp - logp_ref
    @printf "%d,%d,%d,%.12f,%.12f,%.3e\n" seed K N logp logp_ref diff
end
