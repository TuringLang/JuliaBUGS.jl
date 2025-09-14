#!/usr/bin/env julia
using AutoMarginalizationExperiments
using JuliaBUGS
using LogDensityProblems
using Printf
using Random

function hmm_logdensity_with_order(model, θ, order)
    # Prepare caches and offsets as in the benchmark script
    gd = model.graph_evaluation_data
    minimal_keys = AutoMarginalizationExperiments.prepare_minimal_cache_keys(model, order)
    # Build continuous-only param order and offsets
    cont_vars = JuliaBUGS.Model.VarName[]
    var_lengths = Dict{JuliaBUGS.Model.VarName,Int}()
    for vn in gd.sorted_parameters
        idx = findfirst(==(vn), gd.sorted_nodes)
        if idx !== nothing && gd.node_types[idx] == :continuous
            push!(cont_vars, vn)
            var_lengths[vn] = model.transformed_var_lengths[vn]
        end
    end
    offsets = Dict{JuliaBUGS.Model.VarName,Int}()
    start = 1
    for vn in cont_vars
        offsets[vn] = start
        start += var_lengths[vn]
    end
    env = JuliaBUGS.Model.smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    memo = Dict{Tuple{Int,UInt64},Any}()
    return JuliaBUGS.Model._marginalize_recursive(
        model, env, order, θ, offsets, var_lengths, memo, minimal_keys,
    )
end

function peak_frontier_size(minimal_keys)
    isempty(minimal_keys) && return 0
    return maximum((length(v) for v in values(minimal_keys)))
end

function main(; T=300, reps=10, seed=1)
    rng = MersenneTwister(seed)
    data, _ = AutoMarginalizationExperiments.synth_hmm_binary(T; seed=seed)
    model_def = AutoMarginalizationExperiments.build_hmm2_model()
    model, θ = AutoMarginalizationExperiments.compile_autmarg(model_def, data)

    gd = model.graph_evaluation_data
    default_order = isempty(gd.marginalization_order) ? collect(1:length(gd.sorted_nodes)) : gd.marginalization_order
    interleaved = AutoMarginalizationExperiments.build_interleaved_order(model)

    # Warmup
    hmm_logdensity_with_order(model, θ, default_order)
    hmm_logdensity_with_order(model, θ, interleaved)

    # Measure
    function timeit(order)
        t = @elapsed begin
            for _ in 1:reps
                hmm_logdensity_with_order(model, θ, order)
            end
        end
        mk = AutoMarginalizationExperiments.prepare_minimal_cache_keys(model, order)
        return t, peak_frontier_size(mk)
    end

    t_def, w_def = timeit(default_order)
    t_int, w_int = timeit(interleaved)

    l_def = hmm_logdensity_with_order(model, θ, default_order)
    l_int = hmm_logdensity_with_order(model, θ, interleaved)

    @printf "HMM ordering ablation (T=%d, reps=%d)\n" T reps
    @printf " default: time=%.4f s, peak_frontier=%d, logp=%.6f\n" t_def w_def l_def
    @printf " interlv: time=%.4f s, peak_frontier=%d, logp=%.6f\n" t_int w_int l_int
    @printf " abs diff in logp = %.3e\n" abs(l_def - l_int)
end

main()

