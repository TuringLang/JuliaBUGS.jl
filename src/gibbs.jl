struct Gibbs{N,S} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}
end

function Gibbs(model::BUGSModel, s::AbstractMCMC.AbstractSampler)
    return Gibbs(
        OrderedDict([v => s for v in model.graph_evaluation_data.sorted_parameters])
    )
end

abstract type AbstractGibbsState end

struct GibbsState{E<:NamedTuple,S,C} <: AbstractGibbsState
    evaluation_env::E
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
    return model.evaluation_env, GibbsState(model.evaluation_env, conditioning_schedule, cached_eval_caches)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs,
    state::AbstractGibbsState;
    model=l_model.logdensity,
    kwargs...,
)
    evaluation_env = state.evaluation_env
    for vs in keys(state.conditioning_schedule)
        # Update model with current evaluation environment
        model = BangBang.setproperty!!(model, :evaluation_env, evaluation_env)
        cond_model = AbstractPPL.condition(
            model, vs, model.evaluation_env, state.cached_eval_caches[vs]
        )
        # gibbs_internal now returns param_values, need to update evaluation_env
        param_values = gibbs_internal(rng, cond_model, state.conditioning_schedule[vs])
        # Update evaluation_env by setting model with new param values
        model_updated = initialize!(model, param_values)
        evaluation_env = model_updated.evaluation_env
    end
    return evaluation_env,
    GibbsState(evaluation_env, state.conditioning_schedule, state.cached_eval_caches)
end

function gibbs_internal end

function AbstractMCMC.bundle_samples(
    samples::Vector,  # Contains evaluation environments
    logdensitymodel::AbstractMCMC.LogDensityModel{<:JuliaBUGS.BUGSModel},
    sampler::Gibbs,
    states::Vector,
    ::Type{T};
    discard_initial=0,
    kwargs...,
) where {T}
    model = logdensitymodel.logdensity
    
    # Extract parameter values from evaluation environments
    param_samples = Vector{Vector{Float64}}()
    for env in samples
        # Temporarily set the environment to extract parameters
        model_with_env = BangBang.setproperty!!(model, :evaluation_env, env)
        push!(param_samples, JuliaBUGS.getparams(model_with_env))
    end
    
    return JuliaBUGS.gen_chains(
        logdensitymodel, param_samples, [], []; discard_initial=discard_initial, kwargs...
    )
end
