#!/usr/bin/env julia
using AutoMarginalizationExperiments
using JuliaBUGS
using LogDensityProblems
using BenchmarkTools
using Printf

function bench_gmm(; N_list=[1_000, 5_000, 10_000], K=3, reps=10, seed=1)
    @printf "GMM logdensity benchmark (auto-marg), K=%d\n" K
    for N in N_list
        data, _ = AutoMarginalizationExperiments.synth_gmm(N; seed=seed, weights=fill(1/K,K), mus=collect(range(-2,2; length=K)), sigmas=fill(1.0,K))
        dataK = (data..., K=K)
        mdef = AutoMarginalizationExperiments.build_gmm_model(K)
        model, θ = AutoMarginalizationExperiments.compile_autmarg(mdef, dataK)
        # warmup
        LogDensityProblems.logdensity(model, θ)
        b = @benchmark LogDensityProblems.logdensity($model, $θ) samples=$reps evals=1
        @printf "  N=%6d  median=%.3f ms  mean=%.3f ms  allocs=%d  bytes=%d\n" N (median(b).time/1e6) (mean(b).time/1e6) median(b).allocs median(b).memory
    end
end

function bench_hmm(; T_list=[200, 500, 1000], reps=10, seed=1)
    @printf "HMM logdensity benchmark (auto-marg), S=2\n"
    for T in T_list
        data, _ = AutoMarginalizationExperiments.synth_hmm_binary(T; seed=seed)
        mdef = AutoMarginalizationExperiments.build_hmm2_model()
        model, θ = AutoMarginalizationExperiments.compile_autmarg(mdef, data)
        LogDensityProblems.logdensity(model, θ)
        b = @benchmark LogDensityProblems.logdensity($model, $θ) samples=$reps evals=1
        @printf "  T=%6d  median=%.3f ms  mean=%.3f ms  allocs=%d  bytes=%d\n" T (median(b).time/1e6) (mean(b).time/1e6) median(b).allocs median(b).memory
    end
end

bench_gmm()
println()
bench_hmm()

