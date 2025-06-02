struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}
end

function Gibbs(model::BUGSModel, s::AbstractMCMC.AbstractSampler)
    return Gibbs(
        OrderedDict([v => s for v in model.graph_evaluation_data.sorted_parameters])
    )
end

struct MHFromPrior <: AbstractMCMC.AbstractSampler end

abstract type AbstractGibbsState end

struct GibbsState{T,S,C} <: AbstractGibbsState
    values::T
    conditioning_schedule::S
    cached_eval_caches::C
end

ensure_vector(x) = x isa Union{Number,VarName} ? [x] : x

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs{N,S};
    model=l_model.logdensity,
    kwargs...,
) where {N,S}
    cached_eval_caches, conditioning_schedule = OrderedDict(), OrderedDict()
    for variable_group in keys(sampler.sampler_map)
        variable_to_condition_on = setdiff(
            model.graph_evaluation_data.sorted_parameters, ensure_vector(variable_group)
        )
        conditioning_schedule[variable_to_condition_on] = sampler.sampler_map[variable_group]
        conditioned_model = AbstractPPL.condition(
            model, variable_to_condition_on, model.evaluation_env
        )
        cached_eval_caches[variable_to_condition_on] =
            conditioned_model.graph_evaluation_data
    end
    param_values = JuliaBUGS.getparams(model)
    return param_values, GibbsState(param_values, conditioning_schedule, cached_eval_caches)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs,
    state::AbstractGibbsState;
    model=l_model.logdensity,
    kwargs...,
)
    param_values = state.values
    for vs in keys(state.conditioning_schedule)
        model = initialize!(model, param_values)
        cond_model = AbstractPPL.condition(
            model, vs, model.evaluation_env, state.cached_eval_caches[vs]
        )
        param_values = gibbs_internal(rng, cond_model, state.conditioning_schedule[vs])
    end
    return param_values,
    GibbsState(param_values, state.conditioning_schedule, state.cached_eval_caches)
end

function gibbs_internal end

function gibbs_internal(rng::Random.AbstractRNG, cond_model::BUGSModel, ::MHFromPrior)
    transformed_original = JuliaBUGS.getparams(cond_model)
    values, logp = evaluate!!(cond_model, transformed_original)
    values_proposed, logp_proposed = evaluate!!(rng, cond_model)

    if logp_proposed - logp > log(rand(rng))
        values = values_proposed
    end

    return JuliaBUGS.getparams(
        BangBang.setproperty!!(cond_model.base_model, :evaluation_env, values)
    )
end

function AbstractMCMC.bundle_samples(
    ts,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:JuliaBUGS.BUGSModel},
    sampler::Gibbs,
    state,
    ::Type{T};
    discard_initial=0,
    kwargs...,
) where {T}
    return JuliaBUGS.gen_chains(
        logdensitymodel, ts, [], []; discard_initial=discard_initial, kwargs...
    )
end
