module JuliaBUGSFlexiChainsExt

using AbstractMCMC
using FlexiChains: FlexiChains, FlexiChain, VNChain, Parameter, Extra
using JuliaBUGS
using JuliaBUGS:
    BUGSModel,
    BUGSModelWithGradient,
    find_generated_quantities_variables,
    evaluate!!,
    getparams,
    OrderedDict
using JuliaBUGS.Model: UseAutoMarginalization
using JuliaBUGS.AbstractPPL
using JuliaBUGS.AbstractPPL: VarName
using JuliaBUGS.Accessors

function JuliaBUGS.gen_chains(
    chain_type::Type{<:FlexiChain{<:VarName}},
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
    chain_type::Type{<:FlexiChain{<:VarName}},
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

# Values are stored per VarName without flattening, so arrays coming from the
# evaluation environment must be copied before the next evaluation reuses them.
_maybe_copy(x::AbstractArray) = copy(x)
_maybe_copy(x) = x

"""
    gen_chains(
        chain_type::Type{<:FlexiChain{<:VarName}}, model::BUGSModel,
        samples, stats_names, stats_values;
        discard_initial=0, thinning=1, kwargs...
    )

Convert parameter samples to a `FlexiChains.FlexiChain{VarName}` (`VNChain`).

This function:
1. Evaluates the model for each sample to get generated quantities
2. Stores parameters and generated quantities keyed by their `VarName` (array-valued
   variables are kept whole instead of being flattened into scalar columns)
3. Stores sampler statistics as `FlexiChains.Extra` entries
"""
function JuliaBUGS.gen_chains(
    ::Type{<:FlexiChain{<:VarName}},
    model::BUGSModel,
    samples,
    stats_names,
    stats_values;
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    gd = model.graph_evaluation_data
    # Filter parameters based on evaluation mode - only include continuous parameters
    # when auto-marginalization is active (discrete parameters are marginalized out)
    param_vars = if model.evaluation_mode isa UseAutoMarginalization
        mc = model.marginalization_cache
        filter(gd.sorted_parameters) do vn
            idx = findfirst(==(vn), gd.sorted_nodes)
            idx !== nothing && mc.node_types[idx] == :continuous
        end
    else
        gd.sorted_parameters
    end

    # Find and order generated quantities
    # Exclude parameters to avoid double counting forward-sampled variables
    generated_vars = find_generated_quantities_variables(model.g)
    param_set = Set(param_vars)
    generated_vars = [v for v in gd.sorted_nodes if v in generated_vars && v ∉ param_set]

    niters = length(samples)
    dicts = Vector{OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}}(undef, niters)
    for (i, sample) in enumerate(samples)
        # Set parameters and evaluate the model
        evaluation_env = first(evaluate!!(model, sample))

        d = OrderedDict{FlexiChains.ParameterOrExtra{<:VarName},Any}()
        for vn in param_vars
            d[Parameter(vn)] = _maybe_copy(AbstractPPL.getvalue(evaluation_env, vn))
        end
        for vn in generated_vars
            d[Parameter(vn)] = _maybe_copy(AbstractPPL.getvalue(evaluation_env, vn))
        end
        if !isempty(stats_values)
            for (j, name) in enumerate(stats_names)
                d[Extra(Symbol(name))] = stats_values[i][j]
            end
        end
        dicts[i] = d
    end

    return FlexiChain{VarName}(
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
    chain_type::Type{VNChain};
    discard_initial=0,
    kwargs...,
)
    model = logdensitymodel.logdensity

    # Convert evaluation environments to parameter vectors
    param_samples = Vector{Vector{Float64}}()
    for env in samples
        model_with_env = Accessors.@set model.evaluation_env = env
        push!(param_samples, getparams(model_with_env))
    end

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
    chain_type::Type{VNChain};
    kwargs...,
)
    model = logdensitymodel.logdensity

    # Convert evaluation environments to parameter vectors
    param_samples = Vector{Vector{Float64}}()
    for env in samples
        model_with_env = Accessors.@set model.evaluation_env = env
        push!(param_samples, getparams(model_with_env))
    end

    # No per-sample log probabilities available since AbstractMCMC only passes final state
    return JuliaBUGS.gen_chains(
        chain_type, logdensitymodel, param_samples, Symbol[], []; kwargs...
    )
end

end
