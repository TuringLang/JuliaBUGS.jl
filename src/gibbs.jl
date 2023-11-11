struct WithinGibbs{S} <: AbstractMCMC.AbstractSampler
    sampler_map::S # map from a group of variables to the sampler
end

struct MHFromPrior end

struct MHState
    varinfo
    markov_blanket_cache
    sorted_nodes_cache
end
# TODO: need to cache the markov blankets to avoid recomputing them

ensure_vector(x) = x isa Union{Number,VarName} ? [x] : x

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{BUGSModel},
    sampler::WithinGibbs{MHFromPrior};
    model=l_model.logdensity,
    kwargs...,
)
    vi = deepcopy(model.varinfo)
    markov_blanket_cache = Dict{Any,Any}()
    sorted_nodes_cache = Dict{Any,Any}()
    for v in model.parameters
        mb_model = JuliaBUGS.MarkovBlanketBUGSModel(model, v)
        markov_blanket_cache[v] = ensure_vector(mb_model.members)
        sorted_nodes_cache[v] = ensure_vector(mb_model.sorted_nodes)
    end

    init_state = MHState(vi, markov_blanket_cache, sorted_nodes_cache)

    vi = gibbs_steps(rng, model, sampler, init_state)
    return getparams(model, vi), MHState(vi, markov_blanket_cache, sorted_nodes_cache)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    l_model::AbstractMCMC.LogDensityModel{BUGSModel},
    sampler::WithinGibbs{MHFromPrior},
    state::MHState;
    model=l_model.logdensity,
    kwargs...,
)
    vi = state.varinfo
    vi = gibbs_steps(rng, model, sampler, state)
    return getparams(model, vi),
    MHState(vi, state.markov_blanket_cache, state.sorted_nodes_cache)
end

function gibbs_steps(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    ::WithinGibbs{MHFromPrior},
    state,
    var_iterator=model.parameters,
)
    g = model.g
    vi = state.varinfo
    for v in var_iterator
        ni = g[v]
        args = Dict(getsym(arg) => vi[arg] for arg in ni.node_args)
        dist = _eval(ni.node_function_expr.args[2], args)

        transformed_original = ensure_vector(Bijectors.link(dist, vi[v]))
        transformed_proposal = ensure_vector(Bijectors.link(dist, rand(rng, dist)))

        mb_model = JuliaBUGS.MarkovBlanketBUGSModel(
            vi,
            ensure_vector(v),
            state.markov_blanket_cache[v],
            state.sorted_nodes_cache[v],
            model,
        )
        _, logp = evaluate!!(mb_model, LogDensityContext(), transformed_original)
        vi_proposed, logp_proposed = evaluate!!(
            mb_model, LogDensityContext(), transformed_proposal
        )

        logr = logp_proposed - logp
        if logr > log(rand(rng))
            vi = vi_proposed
        end
    end
    return vi
end

function AbstractMCMC.bundle_samples(
    ts,
    logdensitymodel::AbstractMCMC.LogDensityModel{JuliaBUGS.BUGSModel},
    sampler::WithinGibbs{MHFromPrior},
    state,
    ::Type{T};
    discard_initial=0,
    kwargs...,
) where {T}
    return JuliaBUGS.gen_chains(
        logdensitymodel, ts, [], []; discard_initial=discard_initial, kwargs...
    )
end
