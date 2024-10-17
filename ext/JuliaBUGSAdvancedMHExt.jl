module JuliaBUGSAdvancedMHExt

using AbstractMCMC
using AdvancedMH
using JuliaBUGS
using MCMCChains: Chains

using JuliaBUGS:
    BUGSModel,
    Accessors,
    ADTypes,
    LogDensityProblems,
    LogDensityProblemsAD,
    Random,
    gibbs_internal

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

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    sub_model::BUGSModel,
    sampler::AdvancedMH.MHSampler,
    state,
    adtype::ADTypes.AbstractADType,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(adtype, sub_model)
    )

    state = Accessors.@set state.lp = LogDensityProblems.logdensity(sub_model, state.params)

    _, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state)
    return initialize!(sub_model.base_model, s.params).evaluation_env, s
end

end
