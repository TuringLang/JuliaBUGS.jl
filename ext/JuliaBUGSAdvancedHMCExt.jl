module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using JuliaBUGS
using MCMCChains: Chains

using AdvancedHMC: Transition, stat
using JuliaBUGS: AbstractBUGSModel, BUGSModel, Gibbs, find_generated_vars, LogDensityContext, evaluate!!
using JuliaBUGS: BUGSPrimitives, BangBang, LogDensityProblems, LogDensityProblemsAD, Bijectors, Random

import JuliaBUGS: gibbs_internal

function AbstractMCMC.bundle_samples(
    ts::Vector{<:Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat([ts[i].z.ℓπ.value..., collect(values(AdvancedHMC.stat(ts[i])))...]) for
        i in eachindex(ts)
    ]

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        [t.z.θ for t in ts],
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::HMC, adtype::ADTypes.AbstractADType
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(adtype, cond_model)
    )
    t, s = AbstractMCMC.step(
        rng,
        logdensitymodel,
        sampler;
        n_adapts=0,
        initial_params=JuliaBUGS.getparams(cond_model),
    )
    updated_model = initialize!(cond_model, t.z.θ)
    return JuliaBUGS.getparams(
        BangBang.setproperty!!(
            updated_model.base_model, :evaluation_env, updated_model.evaluation_env
        ),
    )
end

end
