module JuliaBUGSAdvancedSliceSamplingExt

using AbstractMCMC
using AdvancedSliceSampling
using ADTypes
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.Random
using MCMCChains: Chains

import JuliaBUGS: gibbs_internal
import AbstractMCMC: step

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedSliceSampling.Sampler,
    state=nothing,
)
    # Use BUGSModel directly as log density (no gradients needed)
    logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)

    # Take slice sampling step
    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng, logdensitymodel, sampler; initial_params=getparams(cond_model)
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state)
    end

    # Handle scalar parameters from slice sampling proposals
    params = !isa(t.params, AbstractArray) ? [t.params] : t.params

    # Update model and return evaluation environment
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, s
end

# Direct AbstractMCMC.step support for BUGSModel with SliceSampling samplers
function step(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    sampler::AdvancedSliceSampling.Sampler;
    kwargs...,
)
    # Wrap BUGSModel as LogDensityModel and delegate to AbstractMCMC.step
    logdensitymodel = AbstractMCMC.LogDensityModel(model)
    return step(rng, logdensitymodel, sampler; kwargs...)
end

# Subsequent step for BUGSModel with state
function step(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    sampler::AdvancedSliceSampling.Sampler,
    state;
    kwargs...,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(model)
    return step(rng, logdensitymodel, sampler, state; kwargs...)
end

# Direct AbstractMCMC.step support for BUGSModelWithGradient with SliceSampling samplers
function step(
    rng::Random.AbstractRNG,
    model::BUGSModelWithGradient,
    sampler::AdvancedSliceSampling.Sampler;
    kwargs...,
)
    # Wrap BUGSModelWithGradient as LogDensityModel and delegate
    logdensitymodel = AbstractMCMC.LogDensityModel(model)
    return step(rng, logdensitymodel, sampler; kwargs...)
end

# Subsequent step for BUGSModelWithGradient with state
function step(
    rng::Random.AbstractRNG,
    model::BUGSModelWithGradient,
    sampler::AdvancedSliceSampling.Sampler,
    state;
    kwargs...,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(model)
    return step(rng, logdensitymodel, sampler, state; kwargs...)
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedSliceSampling.SliceSamplingTransition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::AdvancedSliceSampling.Sampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Extract parameters and log densities
    param_samples = [t.params for t in ts]
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    # Delegate to gen_chains for proper parameter naming
    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedSliceSampling.SliceSamplingTransition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AdvancedSliceSampling.Sampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

end
