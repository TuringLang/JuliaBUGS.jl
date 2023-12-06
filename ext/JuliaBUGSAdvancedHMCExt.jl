module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using AdvancedHMC: Transition, stat
using JuliaBUGS
using JuliaBUGS:
    AbstractBUGSModel,
    BUGSModel,
    Gibbs,
    find_generated_vars,
    LogDensityContext,
    evaluate!!,
    _eval
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.DynamicPPL
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Bijectors
using JuliaBUGS.Random
using MCMCChains: Chains
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
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::HMC
)
    t, s = AbstractMCMC.step(
        rng,
        AbstractMCMC.LogDensityModel(
            LogDensityProblemsAD.ADgradient(:ReverseDiff, cond_model)
        ),
        sampler;
        n_adapts=0,
        initial_params=JuliaBUGS.getparams(cond_model; transformed=true), # for more advanced usage, probably save the state or transition
    )
    return JuliaBUGS.setparams!!(cond_model, t.z.θ; transformed=true)
end

end
