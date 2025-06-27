using DynamicPPL: get_transform_info, invlink
```)  

and these symbols (`get_transform_info`, `invlink`) aren’t used anywhere else in your code —  
the clean fix is simply **delete that line**.  

---

✅ **Here is your cleaned, fixed module without DynamicPPL:**  

```julia
module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, WithGradient, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.Random
using MCMCChains: Chains

import JuliaBUGS: gibbs_internal

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    wrapped::WithGradient{<:AdvancedHMC.AbstractHMCSampler},
    state=nothing,
)
    # Extract sampler and AD backend from wrapper
    return _gibbs_internal_hmc(rng, cond_model, wrapped.sampler, wrapped.ad_backend, state)
end

function _gibbs_internal_hmc(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    # Wrap model with AD gradient computation
    logdensitymodel = AbstractMCMC.LogDensityModel(
        LogDensityProblemsAD.ADgradient(ad_backend, cond_model)
    )

    # Take HMC/NUTS step
    if isnothing(state)
        # Initial step requires initial parameters
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,  # Disable adaptation within Gibbs
            initial_params=getparams(cond_model),
        )
    else
        # Use existing state for subsequent steps
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    # Update model with new parameters and return evaluation environment
    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function JuliaBUGS.update_sampler_state(
    model::BUGSModel,
    sampler::WithGradient{<:AdvancedHMC.AbstractHMCSampler},
    state::AdvancedHMC.HMCState,
)
    # Get updated parameters from model
    θ_new = getparams(model)

    # Recompute log density and gradient at new position
    logdensitymodel = LogDensityProblemsAD.ADgradient(sampler.ad_backend, model)
    ℓ, ∇ℓ = LogDensityProblems.logdensity_and_gradient(logdensitymodel, θ_new)

    # Create new phase point, preserving momentum for detailed balance
    z_new = AdvancedHMC.PhasePoint(
        θ_new,                    # Updated position
        state.transition.z.r,     # Preserve momentum
        AdvancedHMC.DualValue(ℓ, ∇ℓ),  # New log density and gradient
        state.transition.z.ℓκ,    # Preserve kinetic energy
    )

    # Return new state with updated transition but preserved adaptation
    return AdvancedHMC.HMCState(
        state.i,
        AdvancedHMC.Transition(z_new, state.transition.stat),
        state.metric,
        state.κ,
        state.adaptor,
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Extract parameter values and statistics from transitions
    param_samples = [t.z.θ for t in ts]

    # Collect statistic names and values
    # Include log probability and HMC-specific stats (step size, acceptance, etc.)
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat(ts[i].z.ℓπ.value, collect(values(AdvancedHMC.stat(ts[i])))) for
        i in eachindex(ts)
    ]

    # Delegate to gen_chains for proper parameter naming from BUGSModel
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

end # module JuliaBUGSAdvancedHMCExt

