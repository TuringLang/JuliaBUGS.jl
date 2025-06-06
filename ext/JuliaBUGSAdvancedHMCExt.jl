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
import JuliaBUGS: gibbs_internal

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

end
