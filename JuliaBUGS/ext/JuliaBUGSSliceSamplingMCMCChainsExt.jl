module JuliaBUGSSliceSamplingMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using MCMCChains
using SliceSampling

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{MCMCChains.Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_mcmc_stats(ts)

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

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{MCMCChains.Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_mcmc_stats(ts)

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

# --- Transition statistics ----------------------------------------------------
# MCMCChains stores scalar columns, so array-valued `info` entries are flattened
# into one column per element (`key[i,j]`), with `NaN` filling transitions that
# lack a given stat.

_slice_missing_stat(::Real) = NaN

function _slice_stat_name(key::Symbol, index::CartesianIndex)
    return Symbol(string(key), "[", join(Tuple(index), ","), "]")
end

function _slice_flat_info_stat_specs(ts)
    specs = Any[]
    seen = Set{Tuple{Symbol,Any}}()
    for t in ts
        for (key, value) in pairs(t.info)
            if value isa Real
                id = (key, nothing)
                if !(id in seen)
                    push!(seen, id)
                    push!(
                        specs, (name=Symbol(key), key=key, index=nothing, prototype=value)
                    )
                end
            elseif value isa AbstractArray{<:Real}
                for index in CartesianIndices(value)
                    id = (key, index)
                    if !(id in seen)
                        push!(seen, id)
                        push!(
                            specs,
                            (
                                name=_slice_stat_name(key, index),
                                key=key,
                                index=index,
                                prototype=value[index],
                            ),
                        )
                    end
                end
            end
        end
    end
    return specs
end

function _slice_info_stat_value(t, spec)
    if !(spec.key in keys(t.info))
        return _slice_missing_stat(spec.prototype)
    end

    value = getproperty(t.info, spec.key)
    if spec.index === nothing
        return value isa Real ? value : _slice_missing_stat(spec.prototype)
    elseif value isa AbstractArray && spec.index in CartesianIndices(value)
        return value[spec.index]
    else
        return _slice_missing_stat(spec.prototype)
    end
end

function _slice_mcmc_stats(ts)
    specs = _slice_flat_info_stat_specs(ts)
    stats_names = Symbol[:lp]
    append!(stats_names, (spec.name for spec in specs))

    stats_values = Vector{Vector{Real}}(undef, length(ts))
    for (i, t) in enumerate(ts)
        values = Vector{Real}(undef, length(stats_names))
        values[1] = t.lp
        for (j, spec) in enumerate(specs)
            values[j + 1] = _slice_info_stat_value(t, spec)
        end
        stats_values[i] = values
    end
    return stats_names, stats_values
end

end
