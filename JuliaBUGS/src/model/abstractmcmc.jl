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

_build_model(model::BUGSModel, ::Any, ::Nothing) = AbstractMCMC.LogDensityModel(model)
function _build_model(model::BUGSModel, ::Any, adtype::ADTypes.AbstractADType)
    return AbstractMCMC.LogDensityModel(BUGSModelWithGradient(model, adtype))
end

function _prepare_and_sample(rng, model, sampler, args...; adtype, kwargs...)
    return AbstractMCMC.sample(
        rng, _build_model(model, sampler, adtype), sampler, args...; kwargs...
    )
end

# `compile` creates node functions with `Core.eval`, so models compiled and sampled
# within one function cross a world-age boundary. Keep wrapping and sampling in one
# `invokelatest` call. A future compiler should represent node expressions as callable
# data, removing both `Core.eval` and this boundary.
_sample_in_latest_world(args...; kwargs...) =
    Base.invokelatest(_prepare_and_sample, args...; kwargs...)

function AbstractMCMC.sample(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    sampler::AbstractMCMC.AbstractSampler,
    N_or_isdone;
    adtype::Union{Nothing,ADTypes.AbstractADType}=nothing,
    kwargs...,
)
    return _sample_in_latest_world(rng, model, sampler, N_or_isdone; adtype, kwargs...)
end

function AbstractMCMC.sample(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    sampler::AbstractMCMC.AbstractSampler,
    parallel::AbstractMCMC.AbstractMCMCEnsemble,
    N::Integer,
    nchains::Integer;
    adtype::Union{Nothing,ADTypes.AbstractADType}=nothing,
    kwargs...,
)
    return _sample_in_latest_world(
        rng, model, sampler, parallel, N, nchains; adtype, kwargs...
    )
end

# Strip the model wrappers once, so the per-format `gen_chains` methods only need a
# `BUGSModel` method.
function JuliaBUGS.gen_chains(
    chain_type::Type,
    model::Union{BUGSModelWithGradient,AbstractMCMC.LogDensityModel{<:BUGSModelLike}},
    samples,
    draw_stats;
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        chain_type, base_bugs_model(model), samples, draw_stats; kwargs...
    )
end

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

Recover the evaluation environment a draw corresponds to. Environment-based samplers
(`Gibbs`, `IndependentMH`) pass their evaluation environment through
[`transition_params_and_stats`](@ref) whole, so it only needs completing against the model's
own environment; the flat parameter vector other samplers produce is pushed back through the
model, which also returns it to the model's own parameter space.
"""
transition_environment(model::BUGSModel, sampler, transition, params::AbstractVector) =
    first(evaluate!!(model, params))
transition_environment(model::BUGSModel, sampler, transition, params::NamedTuple) =
    merge(model.evaluation_env, params)

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
that report no statistics of their own get the model's log density under `lp`. Samplers
JuliaBUGS does not know how to read (no [`transition_params_and_stats`](@ref) method) keep
AbstractMCMC's generic extraction, exactly as if this method were not defined.
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
    if !params && !stats
        return AbstractMCMC.ParamsWithStats(nothing, NamedTuple(), NamedTuple())
    end

    bugs_model = base_bugs_model(model)
    extracted = JuliaBUGS.transition_params_and_stats(bugs_model, sampler, transition)
    if extracted === nothing
        return invoke(
            AbstractMCMC.ParamsWithStats,
            Tuple{Any,Any,Any,Any},
            model,
            sampler,
            transition,
            state;
            params=params,
            stats=stats,
            extras=extras,
        )
    end
    transition_params, transition_stats = extracted
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
    postprocess_rng(rng, samples, chain_number)

The RNG used to reconstruct generated quantities and marginalized discrete latents.

By default the stream is seeded from the draws themselves and the chain number, so a seeded
sampling run reconstructs identically without any RNG plumbing, and parallel chains get
independent streams with nothing shared across threads. An explicit `rng` is used as given;
that is meant for direct `gen_chains` calls, not for parallel sampling, where it would be
shared across chains.
"""
function postprocess_rng(rng, samples, chain_number)
    rng === nothing || return rng
    return Random.Xoshiro(hash((samples, chain_number)))
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
        evaluation_env, log_densities[i] = draw_environment_and_logp(model, sample)
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
    stats_with_log_density(draw_stats, log_densities)

Report the model's log density as `lp` for draws whose sampler recorded no statistics of its
own, so that every output format carries the standard BUGS diagnostic. Draws that already
carry statistics are left alone. `draw_stats` may be an empty collection (or `nothing`) when
no draw carries statistics.
"""
function stats_with_log_density(draw_stats, log_densities)
    if draw_stats === nothing || isempty(draw_stats)
        return [(lp=logp,) for logp in log_densities]
    end
    return map(draw_stats, log_densities) do stats, logp
        isempty(stats) ? (lp=logp,) : stats
    end
end

"""
    draw_environment_and_logp(model, sample)

Rebuild the evaluation environment and log joint density of one draw. Most samplers produce
a flat parameter vector, which is pushed back through the model; environment-based samplers
(`Gibbs`, `IndependentMH`) carry their evaluation environment through
[`transition_params_and_stats`](@ref) whole, which keeps the values' types — an `Int`-valued
discrete latent stays an `Int` in every output format.
"""
function draw_environment_and_logp(model::BUGSModel, sample::AbstractVector)
    return evaluate!!(model, sample)
end
function draw_environment_and_logp(model::BUGSModel, sample::NamedTuple)
    model_with_env = BangBang.setproperty!!(
        model, :evaluation_env, merge(model.evaluation_env, sample)
    )
    return evaluate!!(model_with_env)
end

"""
    gen_chains(
        ::Type{<:AbstractVector{<:AbstractMCMC.ParamsWithStats}},
        model::BUGSModel,
        samples,
        draw_stats;
        rng=nothing,
        kwargs...,
    )

Lay the draws out as a `Vector` of `AbstractMCMC.ParamsWithStats`, one entry per draw, with
the model parameters and generated quantities together in a [`ParamsDict`](@ref) and the
sampler statistics in a `NamedTuple`.

Unlike the chain formats, a plain vector carries no iteration indices, so `discard_initial`
and `thinning` leave no trace in the result. The reconstruction RNG comes from
[`postprocess_rng`](@ref).
"""
function JuliaBUGS.gen_chains(
    ::Type{<:AbstractVector{<:AbstractMCMC.ParamsWithStats}},
    model::BUGSModel,
    samples,
    draw_stats;
    rng::Union{Nothing,Random.AbstractRNG}=nothing,
    chain_number=nothing,
    kwargs...,
)
    param_vars, generated_vars, param_vals, generated_vals, log_densities = reconstruct_chain_values(
        postprocess_rng(rng, samples, chain_number), model, samples
    )
    draw_stats = stats_with_log_density(draw_stats, log_densities)

    return map(eachindex(samples)) do i
        params = ParamsDict()
        for (j, vn) in enumerate(param_vars)
            params[vn] = param_vals[i][j]
        end
        for (j, vn) in enumerate(generated_vars)
            params[vn] = generated_vals[i][j]
        end
        AbstractMCMC.ParamsWithStats(params, copy_stat_values(draw_stats[i]))
    end
end

# `chain_type = ParamsWithStats` (without the `Vector`) is a likely typo. Without this method
# AbstractMCMC's fallback would hand back the raw transitions.
function JuliaBUGS.gen_chains(
    ::Type{<:AbstractMCMC.ParamsWithStats}, model::BUGSModel, samples, draw_stats; kwargs...
)
    return JuliaBUGS.gen_chains(
        Vector{AbstractMCMC.ParamsWithStats}, model, samples, draw_stats; kwargs...
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
