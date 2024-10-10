module JuliaBUGSAdvancedMHExt

using AbstractMCMC
using AdvancedMH
using JuliaBUGS
using JuliaBUGS: BUGSModel, find_generated_vars, LogDensityContext, evaluate!!
using JuliaBUGS.BUGSPrimitives
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

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::AdvancedMH.MHSampler
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
    updated_model = initialize!(cond_model, t.params)
    return JuliaBUGS.getparams(
        BangBang.setproperty!!(
            updated_model.base_model, :evaluation_env, updated_model.evaluation_env
        ),
    )
end

end
