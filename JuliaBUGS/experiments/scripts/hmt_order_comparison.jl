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

# ==========================
# Env configuration
# ==========================

B = try parse(Int, get(ENV, "AHMT_B", "2")) catch; 2 end
depth = try parse(Int, get(ENV, "AHMT_DEPTH", "8")) catch; 8 end
K = try parse(Int, get(ENV, "AHMT_K", "4")) catch; 4 end
seed = try parse(Int, get(ENV, "AHMT_SEED", "1")) catch; 1 end
trials = try parse(Int, get(ENV, "AHMT_TRIALS", "10")) catch; 10 end
mode = lowercase(get(ENV, "AHMT_MODE", "frontier"))  # frontier | timed | dfs
cost_thresh = try parse(Float64, get(ENV, "AHMT_COST_THRESH", "1.0e8")) catch; 1.0e8 end

function num_nodes(B::Int, depth::Int)
    if depth <= 0
        return 0
    end
    if B == 1
        return depth
    else
        return (B^depth - 1) ÷ (B - 1)
    end
end

function parent_index(i::Int, B::Int)
    i == 1 && return 0
    return fld(i - 2, B) + 1
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

function simulate_hmt(rng::AbstractRNG, B::Int, depth::Int, K::Int; init_probs, transition, means, sigmas)
    N = num_nodes(B, depth)
    z = Vector{Int}(undef, N)
    y = Vector{Float64}(undef, N)

    z[1] = rand(rng, Categorical(init_probs))
    y[1] = rand(rng, Normal(means[z[1]], sigmas[z[1]]))
    for i in 2:N
        p = parent_index(i, B)
        z[i] = rand(rng, Categorical(transition[z[p], :]))
        y[i] = rand(rng, Normal(means[z[i]], sigmas[z[i]]))
    end
    return (; z, y)
end

function hmt_model()
    @bugs begin
        z[1] ~ Categorical(init_probs)
        y[1] ~ Normal(means[z[1]], sigmas[z[1]])
        for i in 2:N
            z[i] ~ Categorical(transition[z[parent[i]], 1:K])
            y[i] ~ Normal(means[z[i]], sigmas[z[i]])
        end
    end
end

function compile_case(B, depth, K, seed)
    rng = MersenneTwister(seed)
    N = num_nodes(B, depth)
    init_probs, transition, means, sigmas = default_params(K)
    sim = simulate_hmt(rng, B, depth, K; init_probs=init_probs, transition=transition, means=means, sigmas=sigmas)

    parent = [parent_index(i, B) for i in 1:N]
    data = (
        B = B,
        depth = depth,
        N = N,
        K = K,
        y = sim.y,
        init_probs = init_probs,
        transition = transition,
        means = means,
        sigmas = sigmas,
        parent = parent,
    )
    return compile_autmarg(hmt_model(), data)
end

function frontier_cost_proxy_for(model; K_hint::Real)
    max_f, mean_f, sum_f, logproxy = frontier_cost_proxy(model; K_hint=K_hint)
    return max_f, mean_f, sum_f, logproxy
end

model, θ0 = compile_case(B, depth, K, seed)

orders = Dict{String,Function}(
    "dfs" => () -> make_model_with_order(model, build_hmt_dfs_order(model; B_hint=B)),
    "bfs" => () -> make_model_with_order(model, build_hmt_bfs_order(model)),
    "random_dfs" => () -> make_model_with_order(model, build_hmt_dfs_order(model; B_hint=B, rng=MersenneTwister(seed+1), randomized=true)),
)

@printf "# HMT order comparison (B=%d, depth=%d, K=%d)\n" B depth K
@printf "# order,B,K,depth,N,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp\n"
for (name, buildfun) in orders
    m2 = buildfun()
    max_f, mean_f, sum_f, logproxy = frontier_cost_proxy_for(m2; K_hint=K)
    do_time = (mode == "timed") || (name == "dfs" && mode != "frontier")
    tmin = NaN
    logp = NaN
    if do_time && logproxy <= log(cost_thresh)
        _ = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
        _ = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
        tmin = @belapsed Base.invokelatest(LogDensityProblems.logdensity, $m2, $θ0) samples=trials evals=1
        logp = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
    end
    # Number of nodes in tree
    N = num_nodes(B, depth)
    @printf "%s,%d,%d,%d,%d,%d,%.3f,%d,%.3e,%s,%s\n" name B K depth N max_f mean_f sum_f logproxy (
        isnan(tmin) ? "NA" : @sprintf("%.6e", tmin)
    ) (
        isnan(logp) ? "NA" : @sprintf("%.12f", logp)
    )
end
