module JuliaBUGSFlexiChainsExt

using AbstractMCMC
using FlexiChains: FlexiChains, Parameter, Extra
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, OrderedDict
using JuliaBUGS.Model:
    BUGSModelLike,
    BUGSParamsWithStats,
    base_bugs_model,
    copy_stat_values,
    postprocess_rng,
    reconstruct_chain_values,
    stats_with_log_density
using JuliaBUGS.AbstractPPL
using JuliaBUGS.AbstractPPL: VarName

function JuliaBUGS.gen_chains(
    chain_type::Type{<:FlexiChains.FlexiChain{<:VarName}},
    model::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    samples,
    draw_stats;
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        chain_type, base_bugs_model(model), samples, draw_stats; kwargs...
    )
end

"""
    gen_chains(
        chain_type::Type{<:FlexiChains.FlexiChain{<:VarName}}, model::BUGSModel,
        samples, draw_stats;
        rng=nothing, discard_initial=0, thinning=1, kwargs...
    )

Convert parameter samples to a `FlexiChains.FlexiChain{VarName}` (`VNChain`).

This function:
1. Reconstructs each draw's full evaluation environment via the shared
   [`reconstruct_chain_values`](@ref) helper (model parameters set from the draw,
   marginalized discrete latents recovered, generated quantities forward-sampled)
2. Stores parameters and generated quantities keyed by their `VarName` (array-valued
   variables are kept whole instead of being flattened into scalar columns)
3. Stores each draw's sampler statistics as `FlexiChains.Extra` entries
"""
function JuliaBUGS.gen_chains(
    ::Type{<:FlexiChains.FlexiChain{<:VarName}},
    model::BUGSModel,
    samples,
    draw_stats;
    rng=nothing,
    chain_number=nothing,
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Reconstruct the per-draw values (model parameters plus forward-sampled generated
    # quantities, with marginalized discrete latents recovered) via the shared helper used
    # by both chain-output extensions. `reconstruct_chain_values` already copies array
    # values, so they can be stored directly.
    param_vars, generated_vars, param_vals, generated_vals, log_densities = reconstruct_chain_values(
        postprocess_rng(rng, samples, chain_number), model, samples
    )
    draw_stats = stats_with_log_density(draw_stats, log_densities)

    niters = length(samples)
    dicts = Vector{OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}}(undef, niters)
    for i in 1:niters
        d = OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}()
        for (j, vn) in enumerate(param_vars)
            d[Parameter(vn)] = param_vals[i][j]
        end
        for (j, vn) in enumerate(generated_vars)
            d[Parameter(vn)] = generated_vals[i][j]
        end
        for (name, value) in pairs(copy_stat_values(draw_stats[i]))
            d[Extra(name)] = value
        end
        dicts[i] = d
    end

    return FlexiChains.FlexiChain{VarName}(
        niters,
        1,
        dicts;
        iter_indices=range(discard_initial + 1; step=thinning, length=niters),
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    chain_type::Type{FlexiChains.VNChain};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

"""
    AbstractMCMC.from_samples(
        ::Type{<:FlexiChains.FlexiChain{<:VarName}},
        draws::AbstractMatrix{<:BUGSParamsWithStats};
        start=1,
        thin=1,
    )

Convert draws sampled with `chain_type = Vector{AbstractMCMC.ParamsWithStats}` into a
`FlexiChains.FlexiChain{VarName}`, keeping array-valued variables whole and storing sampler
statistics as `FlexiChains.Extra` entries. Rows are iterations and columns are chains, so a
single run needs `reshape(draws, :, 1)`.

A plain vector of draws carries no iteration indices, so pass `start` and `thin` to restore
the ones the sampling run had (`start = discard_initial + 1`).
"""
function AbstractMCMC.from_samples(
    ::Type{<:FlexiChains.FlexiChain{<:VarName}},
    draws::AbstractMatrix{<:BUGSParamsWithStats};
    start::Int=1,
    thin::Int=1,
)
    dicts = map(draws) do draw
        d = OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}()
        for (vn, value) in pairs(draw.params)
            d[Parameter(vn)] = value
        end
        for (name, value) in pairs(draw.stats)
            d[Extra(name)] = value
        end
        d
    end
    niters = size(draws, 1)
    return FlexiChains.FlexiChain{VarName}(
        niters, size(draws, 2), dicts; iter_indices=range(start; step=thin, length=niters)
    )
end

end
