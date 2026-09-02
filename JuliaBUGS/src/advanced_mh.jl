function gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler::AdvancedMH.MHSampler,
    state=nothing,
)
    logdensitymodel = AbstractMCMC.LogDensityModel(cond_model)
    transition, state = _step_gibbs_component_after_initialization(
        rng, logdensitymodel, sampler, state; initial_params=getparams(cond_model)
    )

    params = transition.params isa AbstractArray ? transition.params : [transition.params]
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, state
end

function gibbs_internal(
    rng::Random.AbstractRNG,
    cond_model::BUGSModel,
    sampler_tuple::Tuple{<:AdvancedMH.MHSampler,<:ADTypes.AbstractADType},
    state=nothing,
)
    sampler, ad_backend = sampler_tuple
    ad_model = BUGSModelWithGradient(cond_model, ad_backend)
    logdensitymodel = AbstractMCMC.LogDensityModel(ad_model)
    transition, state = _step_gibbs_component_after_initialization(
        rng,
        logdensitymodel,
        sampler,
        state;
        initial_params=getparams(cond_model),
        n_adapts=0,
    )

    params = transition.params isa AbstractArray ? transition.params : [transition.params]
    updated_model = initialize!(cond_model, params)
    return updated_model.evaluation_env, state
end

function transition_params_and_stats(
    ::BUGSModel, ::AdvancedMH.MHSampler, transition::AdvancedMH.AbstractTransition
)
    return transition.params, (; lp=transition.lp, accepted=transition.accepted)
end

function validate_gibbs_component(
    ::BUGSModel, _variables, _node_types, ::AdvancedMH.Ensemble
)
    throw(
        ArgumentError(
            "AdvancedMH.Ensemble cannot update a Gibbs block; use an AdvancedMH " *
            "single-chain sampler.",
        ),
    )
end

function validate_gibbs_component(
    model::BUGSModel,
    variables,
    node_types,
    sampler_tuple::Tuple{<:AdvancedMH.MHSampler,<:ADTypes.AbstractADType},
)
    return validate_gibbs_component(model, variables, node_types, first(sampler_tuple))
end

function AbstractMCMC.setparams!!(
    model::AbstractMCMC.LogDensityModel{<:Model.BUGSModelLike},
    state::AdvancedMH.RobustAdaptiveMetropolisState,
    params,
)
    state = AbstractMCMC.setparams!!(state, params)
    return Accessors.@set state.logprob = LogDensityProblems.logdensity(
        model.logdensity, params
    )
end
