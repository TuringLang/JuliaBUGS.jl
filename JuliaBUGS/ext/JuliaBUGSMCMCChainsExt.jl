module JuliaBUGSMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using JuliaBUGS.Model:
    BUGSModelLike,
    BUGSParamsWithStats,
    base_bugs_model,
    postprocess_rng,
    reconstruct_chain_values,
    stats_with_log_density
using JuliaBUGS.AbstractPPL
using MCMCChains

function JuliaBUGS.gen_chains(
    model::Union{BUGSModelLike,AbstractMCMC.LogDensityModel{<:BUGSModelLike}},
    samples,
    draw_stats;
    kwargs...,
)
    return JuliaBUGS.gen_chains(MCMCChains.Chains, model, samples, draw_stats; kwargs...)
end

function JuliaBUGS.gen_chains(
    chain_type::Type{MCMCChains.Chains},
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
        samples, draw_stats;
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
    draw_stats;
    rng=nothing,
    chain_number=nothing,
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Reconstruct the per-draw values (model parameters plus forward-sampled generated
    # quantities, with marginalized discrete latents recovered) via the shared helper used
    # by both chain-output extensions.
    param_vars, generated_vars, param_vals, generated_vals, log_densities = reconstruct_chain_values(
        postprocess_rng(rng, samples, chain_number), model, samples
    )
    stats_names, stats_values = flatten_stats(
        stats_with_log_density(draw_stats, log_densities)
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
        ::Type{MCMCChains.Chains},
        draws::AbstractMatrix{<:BUGSParamsWithStats};
        start=1,
        thin=1,
    )

Convert draws sampled with `chain_type = Vector{AbstractMCMC.ParamsWithStats}` into an
`MCMCChains.Chains`, flattening array-valued variables into scalar columns. Rows are
iterations and columns are chains, so a single run needs `reshape(draws, :, 1)`.

A plain vector of draws carries no iteration indices, so pass `start` and `thin` to restore
the ones the sampling run had (`start = discard_initial + 1`).
"""
function AbstractMCMC.from_samples(
    ::Type{MCMCChains.Chains},
    draws::AbstractMatrix{<:BUGSParamsWithStats};
    start::Int=1,
    thin::Int=1,
)
    isempty(draws) && throw(ArgumentError("cannot build a chain from zero draws"))

    param_keys = collect(keys(first(draws).params))
    param_leaves = JuliaBUGS.VarName[]
    for vn in param_keys
        append!(param_leaves, elementwise_varnames(vn, first(draws).params[vn]))
    end

    stats_names, stats_values = flatten_stats([d.stats for d in vec(draws)])
    param_symbols = Symbol.(param_leaves)

    niters, nchains = size(draws)
    vals = [
        vcat(
            collect(Iterators.flatten(ordered_param_values(draws[i, j], param_keys))),
            stats_values[(j - 1) * niters + i],
        ) for i in 1:niters, j in 1:nchains
    ]
    ncols = length(param_symbols) + length(stats_names)
    all(row -> length(row) == ncols, vals) ||
        throw(ArgumentError("draws do not all carry the same variable shapes"))

    data = Array{Real}(undef, niters, ncols, nchains)
    for j in 1:nchains, i in 1:niters
        data[i, :, j] = vals[i, j]
    end

    return MCMCChains.Chains(
        MCMCChains.concretize(data),
        vcat(param_symbols, stats_names),
        (parameters=param_symbols, internals=stats_names);
        start=start,
        thin=thin,
    )
end

"""
    flatten_stats(stats)

Lay out the per-draw statistics `NamedTuple`s as scalar columns, since
`MCMCChains.Chains` stores scalars only. Columns are the union of the `(key, index)` pairs
seen across draws, in first-seen order, with numeric array statistics expanded to one column
per element (`key[i,j]`). Draws that do not report a column get `NaN`. Statistics that are
never real numbers get no column at all.
"""
function flatten_stats(stats)
    specs = Any[]
    seen = Set{Tuple{Symbol,Any}}()
    for draw in stats, (key, value) in pairs(draw)
        if value isa Real
            id = (key, nothing)
            if !(id in seen)
                push!(seen, id)
                push!(specs, (name=Symbol(key), key=key, index=nothing))
            end
        elseif value isa AbstractArray{<:Real}
            for index in CartesianIndices(value)
                id = (key, index)
                if !(id in seen)
                    push!(seen, id)
                    push!(specs, (name=indexed_stat_name(key, index), key=key, index=index))
                end
            end
        end
    end

    names = Symbol[spec.name for spec in specs]
    values = [[stat_value(draw, spec) for spec in specs] for draw in stats]
    return names, values
end

# Values are looked up by the first draw's keys, so draws whose dicts iterate in a
# different order still land in the right columns. A missing key throws a `KeyError`.
function ordered_param_values(draw, param_keys)
    length(draw.params) == length(param_keys) ||
        throw(ArgumentError("draws do not all carry the same variables"))
    return (draw.params[k] for k in param_keys)
end

function indexed_stat_name(name, index::CartesianIndex)
    return Symbol(string(name), "[", join(Tuple(index), ","), "]")
end

function stat_value(draw, spec)
    haskey(draw, spec.key) || return NaN
    value = draw[spec.key]
    if spec.index === nothing
        return value isa Real ? value : NaN
    elseif value isa AbstractArray && spec.index in CartesianIndices(value)
        element = value[spec.index]
        return element isa Real ? element : NaN
    else
        return NaN
    end
end

end
