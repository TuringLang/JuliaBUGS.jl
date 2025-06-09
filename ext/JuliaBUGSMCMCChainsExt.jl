module JuliaBUGSMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, find_generated_vars, evaluate!!, getparams
using JuliaBUGS.AbstractPPL
using JuliaBUGS.Accessors
using JuliaBUGS.LogDensityProblemsAD
using MCMCChains: Chains

function JuliaBUGS.gen_chains(
    model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    # Extract BUGSModel and delegate
    return JuliaBUGS.gen_chains(
        model.logdensity, samples, stats_names, stats_values; kwargs...
    )
end

function JuliaBUGS.gen_chains(
    model::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    # Extract BUGSModel from ADGradient wrapper
    bugs_model = model.logdensity.ℓ

    return JuliaBUGS.gen_chains(bugs_model, samples, stats_names, stats_values; kwargs...)
end

# Helper to flatten variable names for chain construction
# Based on DynamicPPL's implementation
varname_leaves(vn::VarName, ::Real) = [vn]

function varname_leaves(vn::VarName, val::AbstractArray{<:Union{Real,Missing}})
    return (
        VarName(vn, Accessors.IndexLens(Tuple(I)) ∘ getoptic(vn)) for
        I in CartesianIndices(val)
    )
end

function varname_leaves(vn::VarName, val::AbstractArray)
    return Iterators.flatten(
        varname_leaves(VarName(vn, Accessors.IndexLens(Tuple(I)) ∘ getoptic(vn)), val[I])
        for I in CartesianIndices(val)
    )
end

function varname_leaves(vn::VarName, val::NamedTuple)
    iter = Iterators.map(keys(val)) do sym
        optic = Accessors.PropertyLens{sym}()
        varname_leaves(VarName(vn, optic ∘ getoptic(vn)), optic(val))
    end
    return Iterators.flatten(iter)
end

"""
    gen_chains(
        model::BUGSModel,
        samples, stats_names, stats_values;
        discard_initial=0, thinning=1, kwargs...
    )

Convert parameter samples to MCMCChains format with proper variable names.

This function:
1. Evaluates the model for each sample to get generated quantities
2. Flattens array parameters into individual chain columns
3. Combines parameters, generated quantities, and statistics
4. Creates a properly formatted Chains object
"""
function JuliaBUGS.gen_chains(
    model::BUGSModel,
    samples,
    stats_names,
    stats_values;
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_vars = model.graph_evaluation_data.sorted_parameters

    # Find and order generated quantities
    generated_vars = find_generated_vars(model.g)
    generated_vars = [
        v for v in model.graph_evaluation_data.sorted_nodes if v in generated_vars
    ]

    # Evaluate model for each sample to get parameter values and generated quantities
    param_vals = []
    generated_quantities = []
    for i in axes(samples)[1]
        evaluation_env = first(evaluate!!(model, samples[i]))
        push!(
            param_vals,
            [AbstractPPL.get(evaluation_env, param_var) for param_var in param_vars],
        )
        push!(
            generated_quantities,
            [
                AbstractPPL.get(evaluation_env, generated_var) for
                generated_var in generated_vars
            ],
        )
    end

    # Flatten variable names for array parameters
    param_name_leaves = collect(
        Iterators.flatten([
            collect(varname_leaves(vn, param_vals[1][i])) for
            (i, vn) in enumerate(param_vars)
        ],),
    )
    generated_varname_leaves = collect(
        Iterators.flatten([
            collect(varname_leaves(vn, generated_quantities[1][i])) for
            (i, vn) in enumerate(generated_vars)
        ],),
    )

    # Flatten values for array parameters
    flattened_param_vals = [collect(Iterators.flatten(p)) for p in param_vals]
    flattened_generated_quantities = [
        collect(Iterators.flatten(gq)) for gq in generated_quantities
    ]

    # Combine all values: parameters, generated quantities, and statistics
    vals = [
        convert(
            Vector{Real},
            vcat(
                flattened_param_vals[i],
                flattened_generated_quantities[i],
                isempty(stats_values) ? [] : stats_values[i],
            ),
        ) for i in axes(samples)[1]
    ]

    # Sanity check
    @assert length(vals[1]) ==
        length(param_name_leaves) +
            length(generated_varname_leaves) +
            length(stats_names)

    # Create chains with proper sections
    return Chains(
        vals,
        vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves), stats_names),
        (
            parameters=vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves)),
            internals=stats_names,
        );
        start=discard_initial + 1,
        thin=thinning,
    )
end

function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::JuliaBUGS.Gibbs,
    states,
    ::Type{Chains};
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
        logdensitymodel, param_samples, [], []; discard_initial=discard_initial, kwargs...
    )
end

function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::JuliaBUGS.MHFromPrior,
    states::Vector,
    ::Type{Chains};
    kwargs...,
)
    model = logdensitymodel.logdensity

    # Convert evaluation environments to parameter vectors
    param_samples = Vector{Vector{Float64}}()
    for env in samples
        model_with_env = Accessors.@set model.evaluation_env = env
        push!(param_samples, getparams(model_with_env))
    end

    # Include log probabilities as statistics
    logps = [state.logp for state in states]
    return JuliaBUGS.gen_chains(
        logdensitymodel, param_samples, [:lp], [[lp] for lp in logps]; kwargs...
    )
end

end
