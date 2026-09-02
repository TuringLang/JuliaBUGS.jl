module JuliaBUGSSliceSamplingExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS:
    BUGSModel,
    BUGSModelWithGradient,
    _require_continuous_gibbs_component,
    _step_gibbs_component_after_initialization,
    getparams,
    initialize!
using Random
using SliceSampling

import JuliaBUGS: gibbs_internal, validate_gibbs_component

function JuliaBUGS.validate_gibbs_component(
    model::BUGSModel, variables, sampler::SliceSampling.AbstractSliceSampling
)
    return _require_continuous_gibbs_component(model, variables, "SliceSampling")
end

function SliceSampling.initial_sample(::Random.AbstractRNG, model::BUGSModel)
    return getparams(model)
end

function SliceSampling.initial_sample(::Random.AbstractRNG, model::BUGSModelWithGradient)
    return getparams(model.base_model)
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::SliceSampling.AbstractSliceSampling,
    state=nothing,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)

    t, s = _step_gibbs_component_after_initialization(
        rng, logdensitymodel, sampler, state; initial_params=getparams(cond_model)
    )

    params = t.params isa AbstractArray ? t.params : [t.params]
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, s
end

function JuliaBUGS.transition_params_and_stats(
    ::BUGSModel, ::SliceSampling.AbstractSliceSampling, t::SliceSampling.Transition
)
    return t.params, merge((; lp=t.lp), t.info)
end

end
