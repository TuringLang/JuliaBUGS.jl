"""
    NestedCut(upstream_sampler, downstream_sampler; inner_steps=10, warm_start=true)

Nested MCMC for a cut model (Plummer 2015). Each step: one transition of `upstream_sampler`
on `cut_upstream_model(model)` targeting p(φ | upstream data), then `inner_steps` transitions
of `downstream_sampler` on `cut_downstream_model(model)` targeting p(θ | φ, downstream data)
at the new φ. With `warm_start=true` the inner chain continues from the previous θ; with
`warm_start=false` θ is redrawn from its prior before each inner run. Stage samplers accept the
same kinds as Gibbs blocks: an AdvancedMH/AdvancedHMC/SliceSampling sampler, a `(sampler, adtype)`
tuple, `EnumeratedSampler()`, or a `Gibbs` built on the corresponding derived model
(`Gibbs(cut_upstream_model(model), ...)` / `Gibbs(cut_downstream_model(model), ...)`).
Finite `inner_steps` makes this an approximation to the cut distribution that improves as the
inner chain converges; a single inner step is exact only when the downstream kernel is an exact
draw (e.g. `EnumeratedSampler`).
"""
struct NestedCut{U,D} <: AbstractMCMC.AbstractSampler
    upstream_sampler::U
    downstream_sampler::D
    inner_steps::Int
    warm_start::Bool
    function NestedCut(
        upstream_sampler::U,
        downstream_sampler::D;
        inner_steps::Int=10,
        warm_start::Bool=true,
    ) where {U,D}
        inner_steps >= 1 || throw(ArgumentError("inner_steps must be at least 1"))
        return new{U,D}(upstream_sampler, downstream_sampler, inner_steps, warm_start)
    end
end

struct NestedCutState{E<:NamedTuple,MU<:BUGSModel,MD<:BUGSModel,SU,SD}
    evaluation_env::E
    upstream_model::MU
    downstream_model::MD
    upstream_state::SU
    downstream_state::SD
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:Model.BUGSModelLike},
    sampler::NestedCut;
    model=Model.base_bugs_model(l_model),
    kwargs...,
)
    upstream = _prepare_gibbs_component_model(
        cut_upstream_model(model), sampler.upstream_sampler, "upstream module"
    )
    downstream = _prepare_gibbs_component_model(
        cut_downstream_model(model), sampler.downstream_sampler, "downstream module"
    )
    isempty(model_parameters(upstream)) &&
        throw(ArgumentError("The upstream module has no parameters"))
    isempty(model_parameters(downstream)) &&
        throw(ArgumentError("The downstream module has no parameters"))
    return model.evaluation_env,
    NestedCutState(model.evaluation_env, upstream, downstream, nothing, nothing)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:Model.BUGSModelLike},
    sampler::NestedCut,
    state::NestedCutState;
    model=Model.base_bugs_model(l_model),
    kwargs...,
)
    upstream = BangBang.setproperty!!(
        state.upstream_model, :evaluation_env, state.evaluation_env
    )
    evaluation_env, upstream_state = update_gibbs_component(
        rng, upstream, sampler.upstream_sampler, state.upstream_state
    )

    downstream = BangBang.setproperty!!(
        state.downstream_model, :evaluation_env, evaluation_env
    )
    downstream_state = state.downstream_state
    if !sampler.warm_start
        evaluation_env = first(
            Model.evaluate_with_rng!!(rng, downstream; transformed=false)
        )
        downstream = BangBang.setproperty!!(downstream, :evaluation_env, evaluation_env)
        downstream_state = nothing
    end
    evaluation_env, downstream_state = update_gibbs_component(
        rng, downstream, sampler.downstream_sampler, downstream_state
    )
    for _ in 2:(sampler.inner_steps)
        downstream = BangBang.setproperty!!(downstream, :evaluation_env, evaluation_env)
        evaluation_env, downstream_state = gibbs_internal(
            rng, downstream, sampler.downstream_sampler, downstream_state
        )
    end
    return evaluation_env,
    NestedCutState(
        evaluation_env,
        state.upstream_model,
        state.downstream_model,
        upstream_state,
        downstream_state,
    )
end

function transition_params_and_stats(::BUGSModel, ::NestedCut, evaluation_env::NamedTuple)
    return evaluation_env, NamedTuple()
end
