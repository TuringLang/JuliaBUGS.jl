module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using ADTypes
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, getparams, initialize!
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.Random

import JuliaBUGS: gibbs_internal

function JuliaBUGS.Model._build_model(
    ::BUGSModel, ::AdvancedHMC.AbstractHMCSampler, ::Nothing
)
    throw(
        ArgumentError(
            "Sampling with HMC or NUTS requires an explicit AD backend. " *
            "Pass `adtype` to `sample`, or sample a `BUGSModelWithGradient`.",
        ),
    )
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler_tuple::Tuple{<:AdvancedHMC.AbstractHMCSampler,<:ADTypes.AbstractADType},
    state=nothing,
)
    # Extract sampler and AD backend from tuple
    sampler, ad_backend = sampler_tuple
    return _gibbs_internal_hmc(rng, cond_model, sampler, ad_backend, state)
end

# Error for plain HMC/NUTS samplers without explicit AD backend
function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedHMC.AbstractHMCSampler,
    state=nothing,
)
    return error(
        "Gradient-based samplers (HMC/NUTS) require an explicit AD backend. " *
        "Use a tuple like ($(typeof(sampler).name.name)(...), AutoMooncake()) or " *
        "($(typeof(sampler).name.name)(...), AutoReverseDiff()) or " *
        "($(typeof(sampler).name.name)(...), AutoForwardDiff()) instead.",
    )
end

function _gibbs_internal_hmc(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler, ad_backend, state
)
    # Create gradient model on-the-fly
    ad_model = BUGSModelWithGradient(cond_model, ad_backend)
    x = getparams(cond_model)
    logdensitymodel = AbstractMCMC.LogDensityModel(ad_model)

    # Take HMC/NUTS step
    if isnothing(state)
        # Initial step requires initial parameters
        t, s = AbstractMCMC.step(
            rng,
            logdensitymodel,
            sampler;
            n_adapts=0,  # Disable adaptation within Gibbs
            initial_params=x,
        )
    else
        # Use existing state for subsequent steps
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    # Update model with new parameters and return evaluation environment
    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function JuliaBUGS.transition_params_and_stats(
    ::BUGSModel, ::AdvancedHMC.AbstractHMCSampler, t::AdvancedHMC.Transition
)
    return t.z.θ, merge((; lp=t.z.ℓπ.value), AdvancedHMC.stat(t))
end

end
