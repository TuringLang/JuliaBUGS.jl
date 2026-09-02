module JuliaBUGSAdvancedHMCExt

using AbstractMCMC
using AdvancedHMC
using ADTypes
using JuliaBUGS
using JuliaBUGS:
    BUGSModel,
    BUGSModelWithGradient,
    _require_continuous_gibbs_component,
    getparams,
    initialize!
using JuliaBUGS.Random

import JuliaBUGS: gibbs_internal, validate_gibbs_component

function JuliaBUGS.validate_gibbs_component(
    ::BUGSModel, _variables, _node_types, ::AdvancedHMC.AbstractHMCSampler
)
    throw(
        ArgumentError(
            "AdvancedHMC samplers in Gibbs require an explicit AD backend; " *
            "pass `(sampler, ad_backend)`.",
        ),
    )
end

function JuliaBUGS.validate_gibbs_component(
    ::BUGSModel,
    variables,
    node_types,
    ::Tuple{<:AdvancedHMC.AbstractHMCSampler,<:ADTypes.AbstractADType},
)
    return _require_continuous_gibbs_component(variables, node_types, "AdvancedHMC")
end

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
    sampler, ad_backend = sampler_tuple
    ad_model = BUGSModelWithGradient(cond_model, ad_backend)
    logdensitymodel = AbstractMCMC.LogDensityModel(ad_model)

    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng, logdensitymodel, sampler; n_adapts=0, initial_params=getparams(cond_model)
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state; n_adapts=0)
    end

    updated_model = initialize!(cond_model, t.z.θ)
    return updated_model.evaluation_env, s
end

function JuliaBUGS.transition_params_and_stats(
    ::BUGSModel, ::AdvancedHMC.AbstractHMCSampler, t::AdvancedHMC.Transition
)
    return t.z.θ, merge((; lp=t.z.ℓπ.value), AdvancedHMC.stat(t))
end

end
