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

# Direct MHSampler
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedMH.MHSampler,
    state=nothing,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)

    if isnothing(state)
        # Initial step
        t, s = AbstractMCMC.step(
            rng, logdensitymodel, sampler; initial_params=JuliaBUGS.getparams(cond_model)
        )
    else
        # Subsequent step with existing state
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state)
    end

    updated_model = initialize!(cond_model, t.params)
    # Return the evaluation_env and the new state
    return updated_model.evaluation_env, s
end

# Handle WithGradient wrapper for MH samplers (for AD-based proposals)
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    wrapped::JuliaBUGS.WithGradient{<:AdvancedMH.MHSampler},
    state=nothing,
)
    return _gibbs_internal_mh(rng, cond_model, wrapped.sampler, wrapped.ad_backend, state)
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

# Override bundle_samples for AdvancedMH transitions with BUGSModel
# This calls JuliaBUGS.gen_chains which handles parameter name extraction
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
    # Extract parameter vectors
    param_samples = [t.params for t in ts]

    # Extract log densities
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    # Use gen_chains which will extract parameter names from the BUGSModel
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

# Override bundle_samples for AdvancedMH transitions with ADGradientWrapper
# This calls JuliaBUGS.gen_chains which handles parameter name extraction
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
    # Extract parameter vectors
    param_samples = [t.params for t in ts]

    # Extract log densities
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    # Use gen_chains which will extract parameter names from the underlying BUGSModel
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
