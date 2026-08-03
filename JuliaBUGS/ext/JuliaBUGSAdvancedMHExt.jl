module JuliaBUGSAdvancedMHExt

using AbstractMCMC
using AdvancedMH
using ADTypes
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.Random

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
    # Create gradient model on-the-fly
    ad_model = BUGSModelWithGradient(cond_model, ad_backend)
    x = getparams(cond_model)
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

function JuliaBUGS.transition_params_and_stats(
    ::BUGSModel, ::AdvancedMH.MHSampler, t::AdvancedMH.AbstractTransition
)
    return t.params, (; lp=t.lp)
end

end
