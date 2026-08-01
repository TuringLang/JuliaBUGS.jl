module JuliaBUGSMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using JuliaBUGS.Model:
    BUGSModelLike, BUGSParamsWithStats, base_bugs_model, reconstruct_chain_values
using JuliaBUGS.AbstractPPL
using MCMCChains
using Random: default_rng

function JuliaBUGS.gen_chains(model, samples, stats_names, stats_values; kwargs...)
    return JuliaBUGS.gen_chains(
        MCMCChains.Chains, model, samples, stats_names, stats_values; kwargs...
    )
end

function JuliaBUGS.gen_chains(
    chain_type::Type{MCMCChains.Chains},
    model::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    samples,
    stats_names,
    stats_values;
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        chain_type, base_bugs_model(model), samples, stats_names, stats_values; kwargs...
    )
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
    ::Type{MCMCChains.Chains},
    model::BUGSModel,
    samples,
    stats_names,
    stats_values;
    rng=default_rng(),
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    stats_names, stats_values = flatten_stats(stats_names, stats_values)

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
    ts::Vector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    chain_type::Type{MCMCChains.Chains};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

"""
    AbstractMCMC.from_samples(
        ::Type{MCMCChains.Chains}, draws::AbstractMatrix{<:BUGSParamsWithStats}
    )

Convert draws sampled with `chain_type = Vector{AbstractMCMC.ParamsWithStats}` into an
`MCMCChains.Chains`, flattening array-valued variables into scalar columns. Rows are
iterations and columns are chains, so a single run needs `reshape(draws, :, 1)`.

All draws must carry the same variables and statistics.
"""
function AbstractMCMC.from_samples(
    ::Type{MCMCChains.Chains}, draws::AbstractMatrix{<:BUGSParamsWithStats}
)
    isempty(draws) && throw(ArgumentError("cannot build a chain from zero draws"))

    first_draw = first(draws)
    param_leaves = JuliaBUGS.VarName[]
    for (vn, value) in pairs(first_draw.params)
        append!(param_leaves, elementwise_varnames(vn, value))
    end

    niters, nchains = size(draws)
    flat_draws = vec(draws)
    stats_names, stats_values = flatten_stats(
        collect(keys(first_draw.stats)), [collect(values(d.stats)) for d in flat_draws]
    )

    vals = Array{Real}(undef, niters, length(param_leaves) + length(stats_names), nchains)
    for j in 1:nchains, i in 1:niters
        k = (j - 1) * niters + i
        row = vcat(
            collect(Iterators.flatten(values(flat_draws[k].params))), stats_values[k]
        )
        if length(row) != size(vals, 2)
            throw(ArgumentError("draws do not all carry the same variables and statistics"))
        end
        vals[i, :, j] = row
    end

    param_symbols = Symbol.(param_leaves)
    return MCMCChains.Chains(
        MCMCChains.concretize(vals),
        vcat(param_symbols, stats_names),
        (parameters=param_symbols, internals=stats_names),
    )
end

"""
    flatten_stats(stats_names, stats_values)

Expand array-valued sampler statistics into one scalar column per element, named
`key[i,j]`, since `MCMCChains.Chains` stores scalars only. Draws that do not carry a value
for a column get `NaN`.
"""
function flatten_stats(stats_names, stats_values)
    isempty(stats_values) && return collect(Symbol, stats_names), stats_values

    specs = Any[]
    for (position, name) in enumerate(stats_names)
        prototype = stat_prototype(stats_values, position)
        if prototype isa AbstractArray
            for index in CartesianIndices(prototype)
                push!(
                    specs,
                    (name=indexed_stat_name(name, index), position=position, index=index),
                )
            end
        else
            push!(specs, (name=Symbol(name), position=position, index=nothing))
        end
    end

    names = Symbol[spec.name for spec in specs]
    values = [[stat_value(draw, spec) for spec in specs] for draw in stats_values]
    return names, values
end

function stat_prototype(stats_values, position)
    for draw in stats_values
        draw[position] isa AbstractArray && return draw[position]
    end
    return first(stats_values)[position]
end

function indexed_stat_name(name, index::CartesianIndex)
    return Symbol(string(name), "[", join(Tuple(index), ","), "]")
end

function stat_value(draw, spec)
    value = draw[spec.position]
    if spec.index === nothing
        return value isa Real ? value : NaN
    elseif value isa AbstractArray && spec.index in CartesianIndices(value)
        return value[spec.index]
    else
        return NaN
    end
end

end
