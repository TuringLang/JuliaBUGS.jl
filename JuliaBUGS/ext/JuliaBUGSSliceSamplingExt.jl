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

# Canonical raw samples keep array-valued sampler statistics whole. Build a common schema
# across all transitions and fill an unavailable statistic with NaNs of the same shape.
_slice_missing_stat(::Real) = NaN
_slice_missing_stat(x::AbstractArray) = fill(NaN, size(x))

_slice_copy_stat(x::AbstractArray) = copy(x)
_slice_copy_stat(x) = x

function _slice_info_key_specs(transitions)
    specs = Any[]
    seen = Set{Symbol}()
    for transition in transitions
        for (key, value) in pairs(transition.info)
            if (value isa Real || value isa AbstractArray{<:Real}) && !(key in seen)
                push!(seen, key)
                push!(specs, (name=Symbol(key), key=key, prototype=value))
            end
        end
    end
    return specs
end

function _slice_stat_value(transition, spec)
    if !(spec.key in keys(transition.info))
        return _slice_missing_stat(spec.prototype)
    end
    return _slice_copy_stat(getproperty(transition.info, spec.key))
end

function _slice_stats(transitions)
    specs = _slice_info_key_specs(transitions)
    names = (:lp, (spec.name for spec in specs)...)
    return map(transitions) do transition
        values = (transition.lp, (_slice_stat_value(transition, spec) for spec in specs)...)
        NamedTuple{names}(values)
    end
end

function JuliaBUGS.Model._transitions_to_params_with_stats(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:Union{BUGSModel,BUGSModelWithGradient}},
    ::SliceSampling.AbstractSliceSampling,
    transitions::AbstractVector{<:SliceSampling.Transition},
)
    model = JuliaBUGS.Model._base_bugs_model(logdensitymodel.logdensity)
    parameter_samples = map(transitions) do transition
        transition.params isa AbstractArray ? transition.params : [transition.params]
    end
    return JuliaBUGS.Model._parameter_samples_to_params_with_stats(
        rng, model, parameter_samples, _slice_stats(transitions)
    )
end

end
