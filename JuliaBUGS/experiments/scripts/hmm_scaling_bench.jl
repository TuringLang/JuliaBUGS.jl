#!/usr/bin/env julia

using Random
using Distributions
using Printf
using Statistics
using BenchmarkTools

include(joinpath(@__DIR__, "..", "utils.jl"))

using JuliaBUGS
using JuliaBUGS: @bugs
JuliaBUGS.@bugs_primitive Categorical Normal
using LogDensityProblems

const JModel = JuliaBUGS.Model

parse_list(str) = begin
    s = strip(str)
    isempty(s) && return Int[]
    if occursin(',', s)
        return parse.(Int, split(s, ","))
    else
        return [parse(Int, s)]
    end
end

seeds = let v = get(ENV, "AS_SWEEP_SEEDS", get(ENV, "AS_SEED", "1"))
    xs = parse_list(v)
    isempty(xs) ? [1] : xs
end
Ks = let v = get(ENV, "AS_SWEEP_K", get(ENV, "AS_K", "2,4"))
    xs = parse_list(v)
    isempty(xs) ? [2, 4] : xs
end
Ts = let v = get(ENV, "AS_SWEEP_T", get(ENV, "AS_T", "50,200"))
    xs = parse_list(v)
    isempty(xs) ? [50, 200] : xs
end
trials = try parse(Int, get(ENV, "AS_TRIALS", "5")) catch; 5 end

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

function frontier_stats(model)
    gd = model.graph_evaluation_data
    order = gd.marginalization_order
    keys = gd.minimal_cache_keys
    widths = [length(get(keys, idx, Int[])) for idx in order]
    if isempty(widths)
        return 0, 0.0, 0
    end
    return maximum(widths), mean(widths), sum(widths)
end

function bench_case(; K::Int, T::Int, seed::Int, trials::Int)
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
    # Always use the interleaved (time-first) order for scaling
    model = make_model_with_order(model, build_interleaved_order(model))
    # Warm-up JIT
    _ = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)
    _ = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)

    # Benchmark with BenchmarkTools; use provided trial count (reports min time)
    mean_time = @belapsed Base.invokelatest(LogDensityProblems.logdensity, $model, $θ0) samples=trials evals=1

    max_frontier, mean_frontier, sum_frontier = frontier_stats(model)
    # Return mean time, last logp, and frontier stats
    logp = Base.invokelatest(LogDensityProblems.logdensity, model, θ0)
    return mean_time, logp, max_frontier, mean_frontier, sum_frontier
end

@printf "# HMM scaling benchmark (auto-marginalization)\n"
@printf "# seed,K,T,trials,min_time_sec,logp,max_frontier,mean_frontier,sum_frontier\n"
for seed in seeds, K in Ks, T in Ts
    mean_time, logp, max_f, mean_f, sum_f = bench_case(K=K, T=T, seed=seed, trials=trials)
    @printf "%d,%d,%d,%d,%.6e,%.12f,%d,%.3f,%d\n" seed K T trials mean_time logp max_f mean_f sum_f
end
