module JuliaBUGSSliceSamplingFlexiChainsExt

using AbstractMCMC
using FlexiChains: FlexiChains
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using SliceSampling

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{FlexiChains.VNChain};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_flexichains_stats(ts)

    return JuliaBUGS.gen_chains(
        chain_type,
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{FlexiChains.VNChain};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_flexichains_stats(ts)

    return JuliaBUGS.gen_chains(
        chain_type,
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

# --- Transition statistics ----------------------------------------------------
# FlexiChains keeps structured values, so array-valued `info` entries are stored
# whole (one column per key) rather than flattened, with `NaN`/`fill(NaN, ...)`
# filling transitions that lack a given stat.

_slice_missing_stat(::Real) = NaN
_slice_missing_stat(x::AbstractArray) = fill(NaN, size(x))

_slice_copy_stat(x::AbstractArray) = copy(x)
_slice_copy_stat(x) = x

function _slice_info_key_specs(ts)
    specs = Any[]
    seen = Set{Symbol}()
    for t in ts
        for (key, value) in pairs(t.info)
            if value isa Real || value isa AbstractArray{<:Real}
                if !(key in seen)
                    push!(seen, key)
                    push!(specs, (name=Symbol(key), key=key, prototype=value))
                end
            end
        end
    end
    return specs
end

function _slice_key_stat_value(t, spec)
    if !(spec.key in keys(t.info))
        return _slice_missing_stat(spec.prototype)
    end

    value = getproperty(t.info, spec.key)
    return _slice_copy_stat(value)
end

function _slice_flexichains_stats(ts)
    specs = _slice_info_key_specs(ts)
    stats_names = Symbol[:lp]
    append!(stats_names, (spec.name for spec in specs))

    stats_values = Vector{Vector{Any}}(undef, length(ts))
    for (i, t) in enumerate(ts)
        values = Vector{Any}(undef, length(stats_names))
        values[1] = t.lp
        for (j, spec) in enumerate(specs)
            values[j + 1] = _slice_key_stat_value(t, spec)
        end
        stats_values[i] = values
    end
    return stats_names, stats_values
end

end
