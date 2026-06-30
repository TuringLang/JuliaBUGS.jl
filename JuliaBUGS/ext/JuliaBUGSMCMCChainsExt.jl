module JuliaBUGSMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using JuliaBUGS.Model: reconstruct_chain_values, param_samples_from_environments
using JuliaBUGS.AbstractPPL
using MCMCChains
using Random: default_rng

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
    model::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    # Extract BUGSModel from gradient wrapper
    bugs_model = model.logdensity.base_model

    return JuliaBUGS.gen_chains(bugs_model, samples, stats_names, stats_values; kwargs...)
end

"""
    elementwise_varnames(vn::VarName, val)

Flatten a variable name into leaf variable names for flat structures only.

This function creates individual `VarName`s for each element in arrays of scalars.
It will throw an error for nested structures (arrays of arrays or NamedTuples).

# Arguments
- `vn::VarName`: The base variable name
- `val`: The value (must be a scalar or flat array of scalars)

# Returns
An iterator of `VarName`s representing all leaf variables

# Examples
```jldoctest
julia> using JuliaBUGS.AbstractPPL: VarName

julia> vn = VarName(:x);

julia> collect(elementwise_varnames(vn, 1.5))
1-element Vector{VarName{:x, Iden}}:
 x

julia> collect(elementwise_varnames(vn, [1.0, 2.0, 3.0]))
3-element Vector{VarName{:x, Index{Tuple{Int64}, @NamedTuple{}, Iden}}}:
 x[1]
 x[2]
 x[3]

julia> collect(elementwise_varnames(vn, [1.0 2.0; 3.0 4.0]))
2×2 Matrix{VarName{:x, Index{Tuple{Int64, Int64}, @NamedTuple{}, Iden}}}:
 x[1, 1]  x[1, 2]
 x[2, 1]  x[2, 2]

julia> elementwise_varnames(vn, [[1.0, 2.0], [3.0, 4.0]])
ERROR: ArgumentError: elementwise_varnames does not support nested structures. Got type Vector{Vector{Float64}} for variable x
[...]

julia> elementwise_varnames(vn, (a=1.0, b=2.0))
ERROR: ArgumentError: elementwise_varnames does not support nested structures. Got type @NamedTuple{a::Float64, b::Float64} for variable x
[...]
```

# Throws
- `ArgumentError`: If `val` contains nested structures
"""
function elementwise_varnames end
elementwise_varnames(vn::JuliaBUGS.VarName, ::Real) = [vn]
function elementwise_varnames(
    vn::JuliaBUGS.VarName{sym}, val::AbstractArray{<:Union{Real,Missing}}
) where {sym}
    current_optic = getoptic(vn)
    return (
        VarName{sym}(AbstractPPL.Index(Tuple(I), (;)) ∘ current_optic) for
        I in CartesianIndices(val)
    )
end
function elementwise_varnames(vn::JuliaBUGS.VarName, val)
    throw(
        ArgumentError(
            "elementwise_varnames does not support nested structures. " *
            "Got type $(typeof(val)) for variable $vn",
        ),
    )
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
    rng=default_rng(),
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Reconstruct the per-draw values (model parameters plus forward-sampled generated
    # quantities, with marginalized discrete latents recovered) via the shared helper used
    # by both chain-output extensions.
    param_vars, generated_vars, param_vals, generated_vals = reconstruct_chain_values(
        rng, model, samples
    )

    # Flatten variable names for array parameters
    param_name_leaves = collect(
        Iterators.flatten([
            collect(elementwise_varnames(vn, param_vals[1][i])) for
            (i, vn) in enumerate(param_vars)
        ],),
    )
    generated_varname_leaves = collect(
        Iterators.flatten([
            collect(elementwise_varnames(vn, generated_vals[1][i])) for
            (i, vn) in enumerate(generated_vars)
        ],),
    )

    # Flatten values for array parameters
    flattened_param_vals = [collect(Iterators.flatten(p)) for p in param_vals]
    flattened_generated_quantities = [
        collect(Iterators.flatten(gq)) for gq in generated_vals
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
    # Note: We include generated quantities in the parameters section for backward compatibility
    # This allows tests and existing code to access all variables via standard MCMCChains methods
    return MCMCChains.Chains(
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
    ::Type{MCMCChains.Chains};
    discard_initial=0,
    kwargs...,
)
    param_samples = param_samples_from_environments(logdensitymodel.logdensity, samples)

    # No statistics for Gibbs sampler itself
    return JuliaBUGS.gen_chains(
        logdensitymodel, param_samples, [], []; discard_initial=discard_initial, kwargs...
    )
end

function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::JuliaBUGS.IndependentMH,
    state,  # Final state only (AbstractMCMC interface)
    ::Type{MCMCChains.Chains};
    kwargs...,
)
    param_samples = param_samples_from_environments(logdensitymodel.logdensity, samples)

    # No per-sample log probabilities available since AbstractMCMC only passes final state
    return JuliaBUGS.gen_chains(logdensitymodel, param_samples, [], []; kwargs...)
end

end
