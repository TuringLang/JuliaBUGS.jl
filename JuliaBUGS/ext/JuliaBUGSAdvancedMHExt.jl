module JuliaBUGSAdvancedMHExt

using AbstractMCMC
using AdvancedMH
using ADTypes
import DifferentiationInterface as DI
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Model: _logdensity_switched
using JuliaBUGS.Random
using MCMCChains: Chains

import JuliaBUGS: gibbs_internal

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedMH.MHSampler,
    state=nothing,
)
    # Use BUGSModel directly as log density (no gradients needed)
    logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)

    # Take MH step
    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng, logdensitymodel, sampler; initial_params=getparams(cond_model)
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state)
    end

    # Handle scalar parameters from some MH proposals
    params = !isa(t.params, AbstractArray) ? [t.params] : t.params

    # Update model and return evaluation environment
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, s
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler_tuple::Tuple{<:AdvancedMH.MHSampler,<:ADTypes.AbstractADType},
    state=nothing,
)
    # Extract sampler and AD backend for gradient-based MH proposals
    sampler, ad_backend = sampler_tuple
    return _gibbs_internal_mh(rng, cond_model, sampler, ad_backend, state)
end

function _gibbs_internal_mh(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    # Create gradient model on-the-fly using DifferentiationInterface
    x = getparams(cond_model)
    prep = DI.prepare_gradient(_logdensity_switched, ad_backend, x, DI.Constant(cond_model))
    ad_model = BUGSModelWithGradient(ad_backend, prep, cond_model)
    logdensitymodel = AbstractMCMC.LogDensityModel(ad_model)

    # Take MH step with gradient information
    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,  # Disable adaptation within Gibbs
            initial_params=x,
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    # Handle scalar parameters and update model
    params = !isa(t.params, AbstractArray) ? [t.params] : t.params
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, s
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:JuliaBUGS.BUGSModel},
    sampler::AdvancedMH.MHSampler,
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
    ts::Vector{<:AdvancedMH.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AdvancedMH.MHSampler,
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

# Keep backward compatibility with LogDensityProblemsAD wrapper
function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Same extraction for gradient-based MH samplers
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
