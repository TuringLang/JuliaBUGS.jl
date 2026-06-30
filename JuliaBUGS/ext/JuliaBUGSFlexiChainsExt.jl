module JuliaBUGSFlexiChainsExt

using AbstractMCMC
using FlexiChains: FlexiChains, Parameter, Extra
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient, OrderedDict
using JuliaBUGS.Model: reconstruct_chain_values, param_samples_from_environments
using JuliaBUGS.AbstractPPL
using JuliaBUGS.AbstractPPL: VarName
using Random: default_rng

function JuliaBUGS.gen_chains(
    chain_type::Type{<:FlexiChains.FlexiChain{<:VarName}},
    model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    # Extract BUGSModel and delegate
    return JuliaBUGS.gen_chains(
        chain_type, model.logdensity, samples, stats_names, stats_values; kwargs...
    )
end

function JuliaBUGS.gen_chains(
    chain_type::Type{<:FlexiChains.FlexiChain{<:VarName}},
    model::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    # Extract BUGSModel from gradient wrapper
    bugs_model = model.logdensity.base_model

    return JuliaBUGS.gen_chains(
        chain_type, bugs_model, samples, stats_names, stats_values; kwargs...
    )
end

"""
    gen_chains(
        chain_type::Type{<:FlexiChains.FlexiChain{<:VarName}}, model::BUGSModel,
        samples, stats_names, stats_values;
        rng=default_rng(), discard_initial=0, thinning=1, kwargs...
    )

Convert parameter samples to a `FlexiChains.FlexiChain{VarName}` (`VNChain`).

This function:
1. Reconstructs each draw's full evaluation environment via the shared
   [`reconstruct_chain_values`](@ref) helper (model parameters set from the draw,
   marginalized discrete latents recovered, generated quantities forward-sampled)
2. Stores parameters and generated quantities keyed by their `VarName` (array-valued
   variables are kept whole instead of being flattened into scalar columns)
3. Stores sampler statistics as `FlexiChains.Extra` entries
"""
function JuliaBUGS.gen_chains(
    ::Type{<:FlexiChains.FlexiChain{<:VarName}},
    model::BUGSModel,
    samples,
    stats_names,
    stats_values;
    rng=default_rng(),
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Reconstruct the per-draw values (model parameters plus forward-sampled generated
    # quantities, with marginalized discrete latents recovered) via the shared helper used
    # by both chain-output extensions. `reconstruct_chain_values` already copies array
    # values, so they can be stored directly.
    param_vars, generated_vars, param_vals, generated_vals = reconstruct_chain_values(
        rng, model, samples
    )

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
        if !isempty(stats_values)
            for (j, name) in enumerate(stats_names)
                d[Extra(Symbol(name))] = stats_values[i][j]
            end
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
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::JuliaBUGS.Gibbs,
    states,
    chain_type::Type{FlexiChains.VNChain};
    discard_initial=0,
    kwargs...,
)
    param_samples = param_samples_from_environments(logdensitymodel.logdensity, samples)

    # No statistics for Gibbs sampler itself
    return JuliaBUGS.gen_chains(
        chain_type,
        logdensitymodel,
        param_samples,
        Symbol[],
        [];
        discard_initial=discard_initial,
        kwargs...,
    )
end

function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::JuliaBUGS.IndependentMH,
    state,  # Final state only (AbstractMCMC interface)
    chain_type::Type{FlexiChains.VNChain};
    kwargs...,
)
    param_samples = param_samples_from_environments(logdensitymodel.logdensity, samples)

    # No per-sample log probabilities available since AbstractMCMC only passes final state
    return JuliaBUGS.gen_chains(
        chain_type, logdensitymodel, param_samples, Symbol[], []; kwargs...
    )
end

end
