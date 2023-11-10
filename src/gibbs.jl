struct WithinGibbs{S} <: AbstractMCMC.AbstractSampler
    # sampler_map # map from a group of variables to the sampler
    sampler::S # for now all parameters are proposed individually and with the same sampler
end

struct MHFromPrior end

struct SimpleSamplerState
    varinfo
end

function gibbs_steps(model, vi, rng, g)
    for v in model.parameters
        mb_model = JuliaBUGS.MarkovBlanketBUGSModel(model, v, vi)
        ni = g[v]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        dist = _eval(expr, args)
        original_value = vi[v]
        proposal = rand(rng, dist)
        transformed_original = Bijectors.link(dist, original_value)
        if transformed_original isa Number
            transformed_original = [transformed_original]
        end
        transformed_proposal = link(dist, proposal)
        if transformed_proposal isa Number
            transformed_proposal = [transformed_proposal]
        end
        vi, logp = evaluate!!(mb_model, LogDensityContext(), transformed_original)
        vi_proposed, logp_proposed = evaluate!!(
            mb_model, LogDensityContext(), transformed_proposal
        )

        # MH step
        logr = logp_proposed - logp
        if logr > log(rand(rng))
            vi = vi_proposed
        end
    end
    return vi
end

# initial step
function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    model::AbstractMCMC.LogDensityModel{BUGSModel},
    sampler::WithinGibbs{MHFromPrior};
    kwargs...,
)
    @info "initial step"
    vi = deepcopy(model.logdensity.varinfo)
    g = model.logdensity.g
    vi = gibbs_steps(model.logdensity, vi, rng, g)

    return getparams(model.logdensity, vi), SimpleSamplerState(varinfo)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    model::AbstractMCMC.LogDensityModel{BUGSModel},
    sampler::WithinGibbs{MHFromPrior},
    state::SimpleSamplerState;
    kwargs...,
)
    vi = state.varinfo
    g = model.logdensity.g
    vi = gibbs_steps(model.logdensity, vi, rng, g)
    return getparams(model.logdensity, vi), SimpleSamplerState(varinfo)
end
