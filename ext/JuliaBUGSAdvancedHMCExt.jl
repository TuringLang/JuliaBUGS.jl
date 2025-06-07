module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using AdvancedHMC: Transition, stat, HMC, NUTS
using JuliaBUGS
using JuliaBUGS:
    AbstractBUGSModel, BUGSModel, Gibbs, find_generated_vars, evaluate!!, initialize!
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BangBang
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Bijectors
using JuliaBUGS.Random
using MCMCChains: Chains
import JuliaBUGS: gibbs_internal, update_sampler_state

# Handle WithGradient wrapper for HMC samplers
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    wrapped::JuliaBUGS.WithGradient{<:AdvancedHMC.AbstractHMCSampler},
    state=nothing,
)
    return _gibbs_internal_hmc(rng, cond_model, wrapped.sampler, wrapped.ad_backend, state)
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
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    updated_model = initialize!(cond_model, t.z.θ)
    # Return the evaluation_env and the new state
    return updated_model.evaluation_env, s
end

# Update HMC/NUTS state to reflect parameter changes from other samplers
function JuliaBUGS.update_sampler_state(
    model::BUGSModel,
    sampler::JuliaBUGS.WithGradient{<:AdvancedHMC.AbstractHMCSampler},
    state::AdvancedHMC.HMCState,
)
    # Get current parameters from the model
    θ_new = JuliaBUGS.getparams(model)

    # Create ADGradient wrapper for log density evaluation
    logdensitymodel = LogDensityProblemsAD.ADgradient(sampler.ad_backend, model)

    # Compute new log density and gradient at the updated position
    ℓ = LogDensityProblems.logdensity(logdensitymodel, θ_new)
    ∇ℓ = LogDensityProblems.logdensity_and_gradient(logdensitymodel, θ_new)[2]

    # Create DualValue with log density and gradient
    ℓπ = AdvancedHMC.DualValue(ℓ, ∇ℓ)

    # Create new phase point with updated position and density
    # Preserve momentum and kinetic energy from previous state
    z_new = AdvancedHMC.PhasePoint(
        θ_new,  # New position
        state.transition.z.r,  # Keep existing momentum
        ℓπ,  # New log density and gradient
        state.transition.z.ℓκ,  # Keep existing kinetic energy
    )

    # Create new transition with updated phase point
    new_transition = AdvancedHMC.Transition(z_new, state.transition.stat)

    # Return updated state preserving adaptation info
    return AdvancedHMC.HMCState(
        state.i, new_transition, state.metric, state.κ, state.adaptor
    )
end

# Override bundle_samples for AdvancedHMC transitions with ADGradientWrapper
# This calls JuliaBUGS.gen_chains which handles parameter name extraction
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
    # Extract parameter vectors
    param_samples = [t.z.θ for t in ts]
    # Extract stats names and values
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat(ts[i].z.ℓπ.value, collect(values(AdvancedHMC.stat(ts[i])))) for
        i in eachindex(ts)
    ]

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
