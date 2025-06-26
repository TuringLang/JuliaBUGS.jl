module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using ADTypes
using JuliaBUGS
using JuliaBUGS: BUGSModel, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Random
using MCMCChains: Chains

import JuliaBUGS: gibbs_internal

"""
    gibbs_internal(rng, cond_model, (sampler, ad_backend), state=nothing)

Use gradient-based samplers within Gibbs with an explicit AD backend.
"""
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler_tuple::Tuple{<:AdvancedHMC.AbstractHMCSampler,<:ADTypes.AbstractADType},
    state=nothing,
)
    sampler, ad_backend = sampler_tuple
    return _gibbs_internal_hmc(rng, cond_model, sampler, ad_backend, state)
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedHMC.AbstractHMCSampler,
    state=nothing,
)
    return error("Gradient-based samplers (HMC/NUTS) require an explicit AD backend. " *
                 "Use a tuple like ($(typeof(sampler).name.name)(...), AutoForwardDiff()) or " *
                 "($(typeof(sampler).name.name)(...), AutoReverseDiff()) instead.")
end

function _gibbs_internal_hmc(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(ad_backend, cond_model)
    )

    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,
            initial_params=getparams(cond_model),
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    using DynamicPPL: get_transform_info, invlink

    param_samples = [t.z.θ for t in ts]
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat(ts[i].z.ℓπ.value, collect(values(AdvancedHMC.stat(ts[i])))) for i in eachindex(ts)
    ]

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

"""
This fallback is for direct use of `HMC` without AD type. It is legacy and may be removed.
"""
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::HMC
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(:ReverseDiff, cond_model)
    )
    t, s = AbstractMCMC.step(
        rng,
        logdensitymodel,
        sampler;
        n_adapts=0,
        initial_params=JuliaBUGS.getparams(cond_model),
    )
    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function AbstractMCMC.step(
    rng::AbstractRNG,
    model::AbstractBUGSModel,
    sampler::HMC;
    n_adapts=0,
    initial_params=nothing,
    kwargs...
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(:ReverseDiff, model)
    )
    t, s = AbstractMCMC.step(
        rng,
        logdensitymodel,
        sampler;
        n_adapts=n_adapts,
        initial_params=initial_params,
        kwargs...
    )

    return t.z.θ, s
end
end # module
