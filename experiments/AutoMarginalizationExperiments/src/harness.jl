using Random
using Printf
using LinearAlgebra
using Distributions
using ADTypes
using LogDensityProblems
using LogDensityProblemsAD

using JuliaBUGS
using JuliaBUGS: compile
const JModel = JuliaBUGS.Model

"""
    compile_autmarg(model_def, data; transformed=true)

Compile a BUGS model, set transformed mode, and UseAutoMarginalization.
Returns the model and a zero vector of appropriate dimension.
"""
function compile_autmarg(model_def, data; transformed=true)
    m = compile(model_def, data)
    m = JModel.settrans(m, transformed)
    m = JModel.set_evaluation_mode(m, JModel.UseAutoMarginalization())
    D = LogDensityProblems.dimension(m)
    return m, zeros(D)
end

"""
    run_nuts(ad_model, n_iter; n_adapts=round(Int, n_iter/2), init_params=zeros(D))

Run a short NUTS chain via AdvancedHMC if available.
"""
function run_nuts(ad_model, n_iter; n_adapts=round(Int, n_iter/2), init_params=nothing, seed=1)
    try
        @eval using AdvancedHMC, AbstractMCMC
    catch
        error("AdvancedHMC not available in this environment. Add it to the project to run NUTS.")
    end
    rng = Random.MersenneTwister(seed)
    D = LogDensityProblems.dimension(ad_model)
    θ0 = isnothing(init_params) ? zeros(D) : init_params
    return AbstractMCMC.sample(rng, ad_model, NUTS(0.65), n_iter; n_adapts=n_adapts, init_params=θ0, progress=false)
end

"""
    run_gmm_autmarg_nuts(N, K; seed=1, n_iter=200)

Synthetic GMM demo: builds data and model, wraps in AD, and samples with NUTS.
Returns `(model, θ0, chain)`; prints a short summary.
"""
function run_gmm_autmarg_nuts(N, K; seed=1, n_iter=200)
    # Build a simple K-component configuration
    weights = fill(1.0 / K, K)
    mus = range(-2.0, 2.0; length=K) |> collect
    sigmas = fill(1.0, K)
    data, truth = AutoMarginalizationExperiments.synth_gmm(N; seed=seed, mus=mus, sigmas=sigmas, weights=weights)
    dataK = (data..., K=K)
    model_def = AutoMarginalizationExperiments.build_gmm_model(K)
    model, θ0 = compile_autmarg(model_def, dataK)
    ad_model = ADgradient(AutoForwardDiff(), model)
    chn = run_nuts(ad_model, n_iter; init_params=θ0, seed=seed)
    println(@sprintf("[GMM] D=%d, n_iter=%d — done", LogDensityProblems.dimension(ad_model), n_iter))
    return model, θ0, chn
end

"""
    run_hmm_autmarg_nuts(T; seed=1, n_iter=200)

Synthetic 2-state HMM demo with Normal emissions; AutoMarg + NUTS on emission params and sigma.
"""
function run_hmm_autmarg_nuts(T; seed=1, n_iter=200)
    data, truth = AutoMarginalizationExperiments.synth_hmm_binary(T; seed=seed)
    model_def = AutoMarginalizationExperiments.build_hmm2_model()
    model, θ0 = compile_autmarg(model_def, data)
    ad_model = ADgradient(AutoForwardDiff(), model)
    chn = run_nuts(ad_model, n_iter; init_params=θ0, seed=seed)
    println(@sprintf("[HMM] D=%d, n_iter=%d — done", LogDensityProblems.dimension(ad_model), n_iter))
    return model, θ0, chn
end
