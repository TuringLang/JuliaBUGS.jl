module JuliaBUGSAdvancedMHExt

using JuliaBUGS
using JuliaBUGS: BUGSModel, find_generated_vars, LogDensityContext, evaluate!!
import JuliaBUGS: gibbs_internal
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.UnPack
using JuliaBUGS.DynamicPPL
using JuliaBUGS: Random, Bijectors
using AbstractMCMC
using AdvancedMH
using MCMCChains: Chains

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.AbstractTransition},
    logdensitymodel::Union{
        AbstractMCMC.LogDensityModel{JuliaBUGS.BUGSModel},
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
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::AdvancedMH.MHSampler
)
    t, s = AbstractMCMC.step(
        rng,
        AbstractMCMC.LogDensityModel(
            LogDensityProblemsAD.ADgradient(:ReverseDiff, cond_model)
        ),
        sampler;
        n_adapts=0,
        initial_params=JuliaBUGS.getparams(cond_model; transformed=true),
    )
    return JuliaBUGS.setparams!!(cond_model, t.params; transformed=true)
end

end
