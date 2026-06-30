using AbstractMCMC: AbstractMCMC

function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::AbstractMCMC.AbstractSampler,
    transition::NamedTuple,
    state;
    params::Bool=true,
    stats::Bool=false,
    extras::Bool=false,
)
    bugs_model = model.logdensity

    transition_env = merge(bugs_model.evaluation_env, transition)
    param_vars = if bugs_model.evaluation_mode isa UseAutoMarginalization
        bugs_model.marginalization_cache.continuous_model_parameters
    else
        model_parameters(bugs_model)
    end

    p = if params
        d = OrderedDict{String,Any}()
        for vn in param_vars
            value = AbstractPPL.getvalue(transition_env, vn)
            d[string(vn)] = value
        end
        [k => v for (k, v) in d]
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

function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AbstractMCMC.AbstractSampler,
    transition::NamedTuple,
    state;
    kwargs...,
)
    base_model = AbstractMCMC.LogDensityModel(model.logdensity.base_model)
    return AbstractMCMC.ParamsWithStats(base_model, sampler, transition, state; kwargs...)
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
