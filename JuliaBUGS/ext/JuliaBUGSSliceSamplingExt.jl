module JuliaBUGSSliceSamplingExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, getparams, initialize!
using Random
using SliceSampling

import JuliaBUGS: gibbs_internal

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

    if isnothing(state)
        t, s = AbstractMCMC.step(
            rng, logdensitymodel, sampler; initial_params=getparams(cond_model)
        )
    else
        t, s = AbstractMCMC.step(rng, logdensitymodel, sampler, state)
    end

    params = t.params isa AbstractArray ? t.params : [t.params]
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, s
end

end
