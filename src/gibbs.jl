struct Gibbs <: AbstractMCMC.AbstractSampler
    sampler_map::Dict{<:Any,<:AbstractMCMC.AbstractSampler}
end

function Gibbs(model, s::AbstractMCMC.AbstractSampler)
    return Gibbs(Dict([v => s for v in model.parameters]))
end

struct MHFromPrior <: AbstractMCMC.AbstractSampler end

abstract type AbstractGibbsState end

struct GibbsState <: AbstractGibbsState
    varinfo::DynamicPPL.SimpleVarInfo
    conditioning_schedule::Dict
    sorted_nodes_cache::Dict
end

ensure_vector(x) = x isa Union{Number,VarName} ? [x] : x

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs;
    model=l_model.logdensity,
    kwargs...,
)
    vi = deepcopy(model.varinfo)
    sorted_nodes_cache = Dict{Any,Any}()

    conditioning_schedule = Dict()
    for vs in keys(sampler.sampler_map)
        vs_complement = setdiff(model.parameters, ensure_vector(vs))
        conditioning_schedule[vs_complement] = sampler.sampler_map[vs]
    end

    for vs in keys(conditioning_schedule)
        cond_model = AbstractPPL.condition(model, vs)
        sorted_nodes_cache[vs] = ensure_vector(cond_model.sorted_nodes)
    end

    return getparams(model, vi; transformed=model.transformed),
    GibbsState(vi, conditioning_schedule, sorted_nodes_cache)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::Gibbs,
    state::AbstractGibbsState;
    model=l_model.logdensity,
    kwargs...,
)
    vi = state.varinfo
    for vs in keys(state.conditioning_schedule)
        cond_model = AbstractPPL.condition(model, vs, vi, state.sorted_nodes_cache[vs])
        vi = gibbs_internal(rng, cond_model, state.conditioning_schedule[vs])
    end
    return getparams(model, vi; transformed=model.transformed),
    GibbsState(vi, state.conditioning_schedule, state.sorted_nodes_cache)
end

function gibbs_internal end

function gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::MHFromPrior
)
    transformed_original = getparams(cond_model, cond_model.varinfo; transformed=true)
    transformed_proposal = getparams(
        cond_model, evaluate!!(cond_model, SamplingContext())[1]; transformed=true
    )

    vi_proposed, logp_proposed = evaluate!!(
        cond_model, LogDensityContext(), transformed_proposal
    )
    vi, logp = evaluate!!(cond_model, LogDensityContext(), transformed_original)

    if logp_proposed - logp > log(rand(rng))
        vi = vi_proposed
    end
    return vi
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
