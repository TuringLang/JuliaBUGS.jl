module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using JuliaBUGS
using MCMCChains: Chains

using AdvancedHMC: Transition, stat
using JuliaBUGS:
    AbstractBUGSModel,
    BUGSModel,
    Gibbs,
    find_generated_quantities_variables,
    LogDensityContext,
    evaluate!!
using JuliaBUGS:
    BUGSPrimitives, Accessors, ADTypes, BangBang, LogDensityProblems, LogDensityProblemsAD, Bijectors, Random

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
    rng::Random.AbstractRNG,
    sub_model::BUGSModel,
    sampler::HMC,
    state,
    adtype::ADTypes.AbstractADType,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(adtype, sub_model)
    )

    hamiltonian = AdvancedHMC.Hamiltonian(state.metric, sub_model)
    state = Accessors.@set state.transition.z = AdvancedHMC.phasepoint(
        hamiltonian, state.transition.z.θ, state.transition.z.r
    )

    _, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    return initialize!(sub_model.base_model, s.transition.z.θ).evaluation_env, s
end

end
