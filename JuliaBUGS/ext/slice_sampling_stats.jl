function _slice_missing_stat(::Real)
    return NaN
end
function _slice_missing_stat(x::AbstractArray)
    return fill(NaN, size(x))
end

function _slice_copy_stat(x::AbstractArray)
    return copy(x)
end
_slice_copy_stat(x) = x

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
