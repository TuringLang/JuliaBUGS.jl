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

"""
    named_parameters(model::BUGSModel, evaluation_env)

Read the sampled parameters out of `evaluation_env` into a [`ParamsDict`](@ref), copying array
values so they do not alias the buffers the next evaluation reuses.
"""
function named_parameters(model::BUGSModel, evaluation_env)
    d = ParamsDict()
    for vn in sampled_parameters(model)
        d[vn] = _maybe_copy_chain_value(AbstractPPL.getvalue(evaluation_env, vn))
    end
    return d
end

"""
    transition_environment(model, sampler, transition, params)

Recover the evaluation environment a draw corresponds to. Samplers whose transition *is* an
evaluation environment override this so the values can be read straight off it; by default the
flat parameter vector is pushed back through the model, which also returns it to the model's
own parameter space.
"""
transition_environment(model::BUGSModel, sampler, transition, params::AbstractVector) =
    first(evaluate!!(model, params))

function model_log_density(model::BUGSModel, evaluation_env)
    log_densities = if model.evaluation_mode isa UseAutoMarginalization
        _, lds = evaluate_with_marginalization_values!!(model, getparams(model, evaluation_env))
        lds
    else
        model_with_env = BangBang.setproperty!!(model, :evaluation_env, evaluation_env)
        _, lds = evaluate_with_env!!(model_with_env; transformed=model.transformed)
        lds
    end
    return log_densities.tempered_logjoint
end

"""
    AbstractMCMC.ParamsWithStats(model, sampler, transition, state; params, stats, extras)

Extract a callback's view of a draw: the parameters the sampler moves, keyed by `VarName`,
and the statistics the sampler reported for that step.

The view holds only what the sampler moves. Generated quantities, and under
`UseAutoMarginalization` the marginalized discrete latents, are reconstructed once at the
end of sampling, so they appear in the sampling output (`chain_type`) but not here. Samplers
that report no statistics of their own get the model's log density under `lp`.
"""
function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    transition,
    state;
    params::Bool=true,
    stats::Bool=false,
    extras::Bool=false,
)
    bugs_model = base_bugs_model(model)
    transition_params, transition_stats = JuliaBUGS.require_transition_params_and_stats(
        bugs_model, sampler, transition
    )
    evaluation_env = if params || (stats && isempty(transition_stats))
        transition_environment(bugs_model, sampler, transition, transition_params)
    else
        nothing
    end

    p = params ? named_parameters(bugs_model, evaluation_env) : nothing
    s = if !stats
        NamedTuple()
    elseif isempty(transition_stats)
        (lp=model_log_density(bugs_model, evaluation_env),)
    else
        copy_stat_values(transition_stats)
    end

    return AbstractMCMC.ParamsWithStats(p, s, NamedTuple())
end

# Chain outputs store one value per draw, so array-valued variables must be copied before the
# next evaluation reuses the environment's buffers.
_maybe_copy_chain_value(x::AbstractArray) = copy(x)
_maybe_copy_chain_value(x) = x

"""
    copy_stat_values(stats::NamedTuple)

Copy array-valued statistics, for the same reason parameter values are copied: a sampler is
free to report a buffer it reuses on the next step.
"""
function copy_stat_values(stats::NamedTuple)
    return NamedTuple{keys(stats)}(map(_maybe_copy_chain_value, values(stats)))
end

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

Returns `(param_vars, generated_vars, param_vals, generated_vals, log_densities)` where:
- `param_vars == model_parameters(model)` and `generated_vars == generated_quantities(model)`
  (disjoint by construction),
- `param_vals[i]` / `generated_vals[i]` hold the values for draw `i`, ordered to match
  `param_vars` / `generated_vars`,
- `log_densities[i]` is the log joint density at draw `i`, which the evaluation computes
  anyway.

Array values are copied per draw, so callers may store them directly without aliasing the
environment buffers that the next evaluation reuses.
"""
function reconstruct_chain_values(rng::Random.AbstractRNG, model::BUGSModel, samples)
    param_vars = model_parameters(model)
    generated_vars = generated_quantities(model)
    param_vals = Vector{Any}(undef, length(samples))
    generated_vals = Vector{Any}(undef, length(samples))
    log_densities = Vector{Float64}(undef, length(samples))
    for (i, sample) in enumerate(samples)
        evaluation_env, log_densities[i] = evaluate!!(model, sample)
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
    return param_vars, generated_vars, param_vals, generated_vals, log_densities
end

"""
    stats_with_log_density(stats, log_densities)

Report the model's log density as `lp` for draws whose sampler recorded no statistics of its
own, so that every output format carries the standard BUGS diagnostic. Draws that already
carry statistics are left alone.
"""
function stats_with_log_density(stats, log_densities)
    return map(stats, log_densities) do draw_stats, logp
        isempty(draw_stats) ? (lp=logp,) : draw_stats
    end
end

"""
    params_from_environment(model, evaluation_env)

Convert the evaluation environment produced by an environment-based sampler (`Gibbs`,
`IndependentMH`) into the flat parameter vector that `gen_chains` consumes.
"""
function params_from_environment(model::BUGSModel, evaluation_env)
    return getparams(Accessors.@set model.evaluation_env = evaluation_env)
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
    stats;
    rng::Random.AbstractRNG=Random.default_rng(),
    kwargs...,
)
    param_vars, generated_vars, param_vals, generated_vals, log_densities = reconstruct_chain_values(
        rng, model, samples
    )
    stats = stats_with_log_density(stats, log_densities)

    return map(eachindex(samples)) do i
        params = ParamsDict()
        for (j, vn) in enumerate(param_vars)
            params[vn] = param_vals[i][j]
        end
        for (j, vn) in enumerate(generated_vars)
            params[vn] = generated_vals[i][j]
        end
        AbstractMCMC.ParamsWithStats(params, copy_stat_values(stats[i]))
    end
end

# `chain_type = ParamsWithStats` (without the `Vector`) is a likely typo. Without this method
# AbstractMCMC's fallback would hand back the raw transitions.
function JuliaBUGS.gen_chains(
    ::Type{<:AbstractMCMC.ParamsWithStats}, model::BUGSModel, samples, stats; kwargs...
)
    return JuliaBUGS.gen_chains(
        Vector{AbstractMCMC.ParamsWithStats}, model, samples, stats; kwargs...
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    chain_type::Type{
        <:Union{AbstractMCMC.ParamsWithStats,AbstractVector{<:AbstractMCMC.ParamsWithStats}}
    };
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

# Sampling without a `chain_type` returns `ParamsWithStats` draws. Samplers JuliaBUGS does
# not know how to read keep AbstractMCMC's behaviour and hand back the raw transitions.
function AbstractMCMC.bundle_samples(
    ts::Vector,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    ::Type{Any};
    kwargs...,
)
    isempty(ts) && return ts
    model = base_bugs_model(logdensitymodel)
    if JuliaBUGS.transition_params_and_stats(model, sampler, first(ts)) === nothing
        return ts
    end
    return JuliaBUGS.bundle_transitions(
        Vector{AbstractMCMC.ParamsWithStats}, logdensitymodel, ts, sampler; kwargs...
    )
end
