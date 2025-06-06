module JuliaBUGSAdvancedMHExt

using AbstractMCMC
using AdvancedMH
using JuliaBUGS
using JuliaBUGS: BUGSModel, find_generated_vars, evaluate!!, initialize!
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BangBang
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Random
using JuliaBUGS.Bijectors
using MCMCChains: Chains
import JuliaBUGS: gibbs_internal

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.AbstractTransition},
    logdensitymodel::Union{
        AbstractMCMC.LogDensityModel{<:JuliaBUGS.BUGSModel},
        AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    },
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        logdensitymodel,
        [t.params for t in ts],
        [:lp],
        [t.lp for t in ts];
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

# Handle WithGradient wrapper for MH samplers
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    wrapped::JuliaBUGS.WithGradient{<:AdvancedMH.MHSampler},
    state=nothing,
)
    return _gibbs_internal_mh(rng, cond_model, wrapped.sampler, wrapped.ad_backend, state)
end

# Direct MHSampler - default to ReverseDiff for backward compatibility
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedMH.MHSampler,
    state=nothing,
)
    return _gibbs_internal_mh(rng, cond_model, sampler, :ReverseDiff, state)
end

# Common implementation
function _gibbs_internal_mh(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(ad_backend, cond_model)
    )

    if isnothing(state)
        # Initial step
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,
            initial_params=JuliaBUGS.getparams(cond_model),
        )
    else
        # Subsequent step with existing state
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    updated_model = initialize!(cond_model, t.params)
    # Return the evaluation_env and the new state
    return updated_model.evaluation_env, s
end

end
