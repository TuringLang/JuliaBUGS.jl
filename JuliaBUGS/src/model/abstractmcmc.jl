using AbstractMCMC: AbstractMCMC

"""
    BUGSModelLike

A `BUGSModel` or a wrapper around one, as accepted by [`base_bugs_model`](@ref).
"""
const BUGSModelLike = Union{BUGSModel,BUGSModelWithGradient}

"""
    base_bugs_model(model)

Unwrap `model` down to the `BUGSModel` it is built on, stripping the
`AbstractMCMC.LogDensityModel` and `BUGSModelWithGradient` wrappers.
"""
base_bugs_model(model::BUGSModel) = model
base_bugs_model(model::BUGSModelWithGradient) = model.base_model
base_bugs_model(model::AbstractMCMC.LogDensityModel) = base_bugs_model(model.logdensity)

"""
    ParamsDict

The parameter container JuliaBUGS stores in `AbstractMCMC.ParamsWithStats`: the variables of
a single draw keyed by `VarName`, with array-valued variables kept whole.
"""
const ParamsDict = OrderedDict{VarName,Any}

"""
    BUGSParamsWithStats

An `AbstractMCMC.ParamsWithStats` holding a [`ParamsDict`](@ref), as produced by sampling a
`BUGSModel` with `chain_type = Vector{AbstractMCMC.ParamsWithStats}`.
"""
const BUGSParamsWithStats = AbstractMCMC.ParamsWithStats{ParamsDict}

"""
    sampled_parameters(model::BUGSModel)

Return the `VarName`s the sampler moves. Under `UseAutoMarginalization` the discrete latents
are summed out of the log density, so only the continuous parameters are sampled.
"""
function sampled_parameters(model::BUGSModel)
    return if model.evaluation_mode isa UseAutoMarginalization
        model.marginalization_cache.continuous_model_parameters
    else
        model_parameters(model)
    end
end

function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    transition::NamedTuple,
    state;
    params::Bool=true,
    stats::Bool=false,
    extras::Bool=false,
)
    bugs_model = base_bugs_model(model)
    transition_env = merge(bugs_model.evaluation_env, transition)

    p = if params
        d = ParamsDict()
        for vn in sampled_parameters(bugs_model)
            d[vn] = _maybe_copy_chain_value(AbstractPPL.getvalue(transition_env, vn))
        end
        d
    else
        nothing
    end

    s = if stats
        log_densities = if bugs_model.evaluation_mode isa UseAutoMarginalization
            _, lds = evaluate_with_marginalization_values!!(
                bugs_model, getparams(bugs_model, transition_env)
            )
            lds
        else
            model_with_env = BangBang.setproperty!!(bugs_model, :evaluation_env, transition_env)
            _, lds = evaluate_with_env!!(model_with_env; transformed=bugs_model.transformed)
            lds
        end
        (lp=log_densities.tempered_logjoint,)
    else
        NamedTuple()
    end

    e = extras ? NamedTuple() : NamedTuple()

    return AbstractMCMC.ParamsWithStats(p, s, e)
end

# Chain outputs store one value per draw, so array-valued variables must be copied before the
# next evaluation reuses the environment's buffers.
_maybe_copy_chain_value(x::AbstractArray) = copy(x)
_maybe_copy_chain_value(x) = x

"""
    reconstruct_chain_values(rng, model, samples)

Reconstruct the per-draw values reported by `gen_chains`. This is the shared core of the
MCMCChains and FlexiChains output extensions, which differ only in how they lay the values
out (flattened scalar columns vs. whole variables keyed by `VarName`).

For each parameter draw in `samples`, the full evaluation environment is rebuilt: the model
parameters are set from the draw, any marginalized discrete latents are recovered from their
conditional posterior `p(z | θ, y)`, and the generated quantities are forward-sampled. This
matters because `evaluate!!` leaves generated quantities at stale environment values, so the
reported draws would otherwise be wrong; forward-sampling makes them genuine
posterior(-predictive) draws.

Returns `(param_vars, generated_vars, param_vals, generated_vals)` where:
- `param_vars == model_parameters(model)` and `generated_vars == generated_quantities(model)`
  (disjoint by construction),
- `param_vals[i]` / `generated_vals[i]` hold the values for draw `i`, ordered to match
  `param_vars` / `generated_vars`.

Array values are copied per draw, so callers may store them directly without aliasing the
environment buffers that the next evaluation reuses.
"""
function reconstruct_chain_values(rng::Random.AbstractRNG, model::BUGSModel, samples)
    param_vars = model_parameters(model)
    generated_vars = generated_quantities(model)
    param_vals = Vector{Any}(undef, length(samples))
    generated_vals = Vector{Any}(undef, length(samples))
    for (i, sample) in enumerate(samples)
        evaluation_env = first(evaluate!!(model, sample))
        evaluation_env = forward_sample_generated_quantities!!(rng, model, evaluation_env)
        param_vals[i] = Any[
            _maybe_copy_chain_value(AbstractPPL.getvalue(evaluation_env, vn)) for
            vn in param_vars
        ]
        generated_vals[i] = Any[
            _maybe_copy_chain_value(AbstractPPL.getvalue(evaluation_env, vn)) for
            vn in generated_vars
        ]
    end
    return param_vars, generated_vars, param_vals, generated_vals
end

"""
    param_samples_from_environments(model, evaluation_envs)

Convert the evaluation environments produced by environment-based samplers (`Gibbs`,
`IndependentMH`) into the flat parameter vectors that `gen_chains` consumes, by reading
`getparams` from each environment. Shared by the `bundle_samples` methods of the chain-output
extensions, which differ only in the chain type they target.
"""
function param_samples_from_environments(model::BUGSModel, evaluation_envs)
    param_samples = Vector{Vector{Float64}}()
    for env in evaluation_envs
        model_with_env = Accessors.@set model.evaluation_env = env
        push!(param_samples, getparams(model_with_env))
    end
    return param_samples
end

"""
    gen_chains(
        ::Type{<:AbstractVector{<:AbstractMCMC.ParamsWithStats}},
        model::BUGSModel,
        samples,
        stats_names,
        stats_values;
        rng=Random.default_rng(),
        kwargs...,
    )

Lay the draws out as a `Vector` of `AbstractMCMC.ParamsWithStats`, one entry per draw, with
the model parameters and generated quantities together in a [`ParamsDict`](@ref) and the
sampler statistics in a `NamedTuple`.

Unlike the chain formats, a plain vector carries no iteration indices, so `discard_initial`
and `thinning` leave no trace in the result.
"""
function JuliaBUGS.gen_chains(
    ::Type{<:AbstractVector{<:AbstractMCMC.ParamsWithStats}},
    model::BUGSModel,
    samples,
    stats_names,
    stats_values;
    rng::Random.AbstractRNG=Random.default_rng(),
    kwargs...,
)
    param_vars, generated_vars, param_vals, generated_vals = reconstruct_chain_values(
        rng, model, samples
    )
    stat_keys = Tuple(Symbol.(stats_names))

    return map(eachindex(samples)) do i
        params = ParamsDict()
        for (j, vn) in enumerate(param_vars)
            params[vn] = param_vals[i][j]
        end
        for (j, vn) in enumerate(generated_vars)
            params[vn] = generated_vals[i][j]
        end
        stats = if isempty(stat_keys)
            NamedTuple()
        else
            NamedTuple{stat_keys}(Tuple(stats_values[i]))
        end
        AbstractMCMC.ParamsWithStats(params, stats)
    end
end

function AbstractMCMC.bundle_samples(
    ts::Vector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    chain_type::Type{<:AbstractVector{<:AbstractMCMC.ParamsWithStats}};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end
