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

function JuliaBUGS.transition_params_and_stats(
    ::BUGSModel,
    ts::Vector{<:SliceSampling.Transition},
    ::SliceSampling.AbstractSliceSampling,
)
    specs = _info_stat_specs(ts)
    stats_names = Symbol[:lp]
    append!(stats_names, (spec.name for spec in specs))

    stats_values = Vector{Vector{Any}}(undef, length(ts))
    for (i, t) in enumerate(ts)
        values = Vector{Any}(undef, length(stats_names))
        values[1] = t.lp
        for (j, spec) in enumerate(specs)
            values[j + 1] = _info_stat_value(t, spec)
        end
        stats_values[i] = values
    end
    return [t.params for t in ts], stats_names, stats_values
end

# --- Transition statistics ----------------------------------------------------
# Statistics are reported whole, one entry per `info` key, so array-valued entries keep their
# shape. Transitions lacking a key get `NaN`s shaped like the first value seen for it.

_missing_stat(::Real) = NaN
_missing_stat(x::AbstractArray) = fill(NaN, size(x))

_copy_stat(x::AbstractArray) = copy(x)
_copy_stat(x) = x

function _info_stat_specs(ts)
    specs = Any[]
    seen = Set{Symbol}()
    for t in ts
        for (key, value) in pairs(t.info)
            if (value isa Real || value isa AbstractArray{<:Real}) && !(key in seen)
                push!(seen, key)
                push!(specs, (name=Symbol(key), key=key, prototype=value))
            end
        end
    end
    return specs
end

function _info_stat_value(t, spec)
    spec.key in keys(t.info) || return _missing_stat(spec.prototype)
    return _copy_stat(getproperty(t.info, spec.key))
end

end
