struct Gibbs{N,S,ADT<:ADTypes.AbstractADType} <: AbstractMCMC.AbstractSampler
    sampler_map::OrderedDict{N,S}
    adtype::ADT
end

function verify_sampler_map(model::BUGSModel, sampler_map::OrderedDict)
    all_variables_in_keys = Set(Iterators.flatten(keys(sampler_map)))
    model_parameters = Set(model.parameters)

    # Check for extra variables in sampler_map that are not in model parameters
    extra_variables = setdiff(all_variables_in_keys, model_parameters)
    if !isempty(extra_variables)
        throw(
            ArgumentError(
                "Sampler map contains variables not in the model: $extra_variables"
            ),
        )
    end

    # Check for model parameters not covered by sampler_map
    left_over_variables = setdiff(model_parameters, all_variables_in_keys)
    if !isempty(left_over_variables)
        throw(
            ArgumentError(
                "Some model parameters are not covered by the sampler map: $left_over_variables",
            ),
        )
    end

    return true
end

"""
    _create_submodel_for_gibbs_sampling(model::BUGSModel, variables_to_update::Vector{<:VarName})

Internal function to create a conditioned model for Gibbs sampling. This is different from conditioning, because conditioning
only marks a model parameter as observation, while the function effectively creates a sub-model with only the variables in the
Markov blanket of the variables that are being updated.
"""
_create_submodel_for_gibbs_sampling(model::BUGSModel, variables_to_update::VarName) =
    _create_submodel_for_gibbs_sampling(model, [variables_to_update])
function _create_submodel_for_gibbs_sampling(
    model::BUGSModel, variables_to_update::NTuple{N,<:VarName}
) where {N}
    return _create_submodel_for_gibbs_sampling(model, collect(variables_to_update))
end
function _create_submodel_for_gibbs_sampling(
    model::BUGSModel, variables_to_update::Vector{<:VarName}
)
    markov_blanket = markov_blanket(model.g, variables_to_update)
    mb_without_variables_to_update = setdiff(markov_blanket, variables_to_update)
    random_variables_in_mb = filter(
        Base.Fix1(is_stochastic, model.g), mb_without_variables_to_update
    )
    observed_random_variables_in_mb = filter(
        Base.Fix1(is_observation, model.g), random_variables_in_mb
    )
    model_parameters_in_mb = setdiff(
        random_variables_in_mb, observed_random_variables_in_mb
    )
    sub_model = BUGSModel(
        model; parameters=variables_to_update, sorted_nodes=markov_blanket
    )
    return condition(sub_model, model_parameters_in_mb)
end

struct GibbsState{T,S,C}
    evaluation_env::T
    sub_model_cache::C
    sub_states::S
end

function gibbs_internal end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs;
    model=logdensitymodel.logdensity,
    kwargs...,
)
    verify_sampler_map(model, sampler.sampler_map)

    submodel_cache = Vector{BUGSModel}(undef, length(sampler.sampler_map))
    sub_states = Any[]
    for (i, variable_group) in enumerate(keys(sampler.sampler_map))
        submodel = _create_submodel_for_gibbs_sampling(model, variable_group)
        sublogdensitymodel = AbstractMCMC.LogDensityModel(
            LogDensityProblemsAD.ADgradient(sampler.adtype, submodel)
        )
        _, s = AbstractMCMC.step(
            rng, sublogdensitymodel, sampler.sampler_map[variable_group]
        )
        submodel_cache[i] = s
        push!(sub_states, s)
    end

    return getparams(model),
    GibbsState(model.evaluation_env, submodel_cache, map(identity, sub_states))
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs,
    state::GibbsState;
    model=logdensitymodel.logdensity,
    kwargs...,
)
    evaluation_env = state.evaluation_env
    for (i, vs) in enumerate(keys(sampler.sampler_map))
        sub_model = BangBang.setproperty!!(model, :evaluation_env, evaluation_env)
        evaluation_env = gibbs_internal(rng, sub_model, sampler.sampler_map[vs])
    end
    return getparams(model), GibbsState(evaluation_env, state.sub_model_cache)
end

struct MHFromPrior <: AbstractMCMC.AbstractSampler end

struct MHState{T}
    evaluation_env::T
    logp::Float64
end

function gibbs_internal(
    rng::Random.AbstractRNG,
    sub_model::BUGSModel,
    ::MHFromPrior,
    state::MHState,
    adtype::ADTypes.AbstractADType,
)
    evaluation_env, logp = evaluate!!(sub_model, DefaultContext())
    proposed_evaluation_env, logp_proposed = evaluate!!(sub_model, SamplingContext())

    if logp_proposed - logp > log(rand(rng))
        evaluation_env = proposed_evaluation_env
    end

    return MHState(evaluation_env, logp)
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
