module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using AdvancedHMC: Transition, stat, HMC, NUTS
using JuliaBUGS
using JuliaBUGS: AbstractBUGSModel, BUGSModel, Gibbs, find_generated_vars, evaluate!!, initialize!
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BangBang
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

# Handle WithGradient wrapper for HMC samplers
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, wrapped::JuliaBUGS.WithGradient{<:AdvancedHMC.AbstractHMCSampler}, state=nothing
)
    return _gibbs_internal_hmc(rng, cond_model, wrapped.sampler, wrapped.ad_backend, state)
end

# Direct HMC/NUTS - default to ReverseDiff for backward compatibility
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::AdvancedHMC.AbstractHMCSampler, state=nothing
)
    return _gibbs_internal_hmc(rng, cond_model, sampler, :ReverseDiff, state)
end

# Common implementation
function _gibbs_internal_hmc(
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
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler,
            state;
            n_adapts=0,
        )
    end
    
    updated_model = initialize!(cond_model, t.z.θ)
    # Return the evaluation_env and the new state
    return updated_model.evaluation_env, s
end

end
