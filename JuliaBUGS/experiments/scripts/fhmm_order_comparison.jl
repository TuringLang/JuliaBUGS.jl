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

# Env configuration
C = try parse(Int, get(ENV, "AFH_C", "2")) catch; 2 end
K = try parse(Int, get(ENV, "AFH_K", "4")) catch; 4 end
T = try parse(Int, get(ENV, "AFH_T", "100")) catch; 100 end
seed = try parse(Int, get(ENV, "AFH_SEED", "1")) catch; 1 end
trials = try parse(Int, get(ENV, "AFH_TRIALS", "10")) catch; 10 end
mode = lowercase(get(ENV, "AFH_MODE", "frontier"))  # frontier | timed
cost_thresh = try parse(Float64, get(ENV, "AFH_COST_THRESH", "1.0e8")) catch; 1.0e8 end

function default_fhmm_params(C, K)
    init_probs = fill(1.0 / K, C, K)
    diag = 0.9
    off = (1.0 - diag) / (K - 1)
    transition = Array{Float64}(undef, C, K, K)
    for c in 1:C, i in 1:K, j in 1:K
        transition[c, i, j] = off
    end
    for c in 1:C, k in 1:K
        transition[c, k, k] = diag
    end
    mu = Array{Float64}(undef, C, K)
    for c in 1:C
        mu[c, :] = collect(range(-1.5, 1.5; length=K))
    end
    sigma_y = 0.7
    return init_probs, transition, mu, sigma_y
end

function simulate_fhmm(rng::AbstractRNG, C::Int, K::Int, T::Int; init_probs, transition, mu, sigma_y)
    z = Array{Int}(undef, C, T)
    y = Vector{Float64}(undef, T)
    # Initial states
    for c in 1:C
        z[c, 1] = rand(rng, Categorical(Vector(view(init_probs, c, 1:K))))
    end
    y[1] = rand(rng, Normal(sum(mu[c, z[c, 1]] for c in 1:C), sigma_y))
    # Transitions
    for t in 2:T
        for c in 1:C
            z[c, t] = rand(rng, Categorical(Vector(view(transition, c, z[c, t - 1], 1:K))))
        end
        y[t] = rand(rng, Normal(sum(mu[c, z[c, t]] for c in 1:C), sigma_y))
    end
    return (; z, y)
end

function fhmm_model()
    @bugs begin
        # Initial states
        for c in 1:C
            z[c, 1] ~ Categorical(init_probs[c, 1:K])
        end
        # Emission mean at t=1 via cumulative sum over chains
        s[1, 1] = mu[1, z[1, 1]]
        for c in 2:C
            s[c, 1] = s[c - 1, 1] + mu[c, z[c, 1]]
        end
        y[1] ~ Normal(s[C, 1], sigma_y)

        # Transitions and emissions for t >= 2
        for t in 2:T
            for c in 1:C
                z[c, t] ~ Categorical(transition[c, z[c, t - 1], 1:K])
            end
            s[1, t] = mu[1, z[1, t]]
            for c in 2:C
                s[c, t] = s[c - 1, t] + mu[c, z[c, t]]
            end
            y[t] ~ Normal(s[C, t], sigma_y)
        end
    end
end

function frontier_stats_for(model)
    gd = model.graph_evaluation_data
    order = gd.marginalization_order
    keys = gd.minimal_cache_keys
    widths = [length(get(keys, idx, Int[])) for idx in order]
    if isempty(widths)
        return 0, 0.0, 0
    end
    return maximum(widths), mean(widths), sum(widths)
end

# Simulate data
rng = MersenneTwister(seed)
init_probs, transition, mu, sigma_y = default_fhmm_params(C, K)
sim = simulate_fhmm(rng, C, K, T; init_probs=init_probs, transition=transition, mu=mu, sigma_y=sigma_y)

# Build and compile model
model_def = fhmm_model()
data = (
    C = C,
    K = K,
    T = T,
    y = sim.y,
    init_probs = init_probs,
    transition = transition,
    mu = mu,
    sigma_y = sigma_y,
)
model, θ0 = compile_autmarg(model_def, data)

# Define all available orders
orders = Dict{String,Function}(
    "interleaved"     => () -> make_model_with_order(model, build_fhmm_interleaved_order(model)),
    "states_then_y"   => () -> make_model_with_order(model, build_fhmm_states_then_emissions_order(model)),
    "min_fill"        => () -> make_model_with_order(model, build_min_fill_order(model; rng=MersenneTwister(seed+2), num_restarts=3)),
    "min_degree"      => () -> make_model_with_order(model, build_min_degree_order(model; rng=MersenneTwister(seed+3), num_restarts=3)),
)

function parse_orders_env(default_list)
    s = lowercase(strip(get(ENV, "AFH_ORDERS", "")))
    if isempty(s)
        return default_list
    end
    names = [strip(x) for x in split(s, ',') if !isempty(strip(x))]
    # Filter to known orders; keep input order
    selected = [nm for nm in names if haskey(orders, nm)]
    return isempty(selected) ? default_list : selected
end

selected_orders = parse_orders_env(["interleaved", "states_then_y"])

@printf "# FHMM order comparison (C=%d, K=%d, T=%d)\n" C K T
@printf "# order,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp\n"
logp_ref = nothing
for name in selected_orders
    buildfun = orders[name]
    m2 = buildfun()
    # Frontier stats and cost proxy (use K as hint)
    max_f, mean_f, sum_f, logproxy = frontier_cost_proxy(m2; K_hint=K)
    # Timing policy: always time interleaved; only time bad order if proxy ≤ threshold or AFH_MODE=timed
    do_time = (name == "interleaved") || (mode == "timed")
    tmin = NaN
    logp = NaN
    # Compare exp(logproxy) with threshold without overflow by comparing logs
    if do_time && (name == "interleaved" || logproxy <= log(cost_thresh))
        _ = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
        _ = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
        tmin = @belapsed Base.invokelatest(LogDensityProblems.logdensity, $m2, $θ0) samples=trials evals=1
        logp = Base.invokelatest(LogDensityProblems.logdensity, m2, θ0)
        if logp_ref === nothing
            global logp_ref = logp
        end
    end
    @printf "%s,%d,%.3f,%d,%.3e,%s,%s\n" name max_f mean_f sum_f logproxy (
        isnan(tmin) ? "NA" : @sprintf("%.6e", tmin)
    ) (
        isnan(logp) ? "NA" : @sprintf("%.12f", logp)
    )
end
