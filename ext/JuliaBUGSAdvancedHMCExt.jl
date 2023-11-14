module JuliaBUGSAdvancedHMCExt

# The main purpose of this extension is to add `generated_quantities` to the final chains.
# So directly calling the AdvancedHMCMCMCChainsExt is not feasible.

using JuliaBUGS
using JuliaBUGS:
    AbstractBUGSModel,
    find_generated_vars,
    LogDensityContext,
    evaluate!!,
    _eval,
    ensure_vector,
    BUGSModel,
    MarkovBlanketBUGSModel,
    WithinGibbs
import JuliaBUGS: gibbs_steps
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.DynamicPPL
using JuliaBUGS.Bijectors
using JuliaBUGS.Random
using AbstractMCMC
using MCMCChains: Chains
using AdvancedHMC
using AdvancedHMC: Transition, stat

function AbstractMCMC.bundle_samples(
    ts::Vector{<:Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat([ts[i].z.ℓπ.value..., collect(values(AdvancedHMC.stat(ts[i])))...]) for
        i in eachindex(ts)
    ]

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        [t.z.θ for t in ts],
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function gibbs_steps(
    rng::Random.AbstractRNG,
    model::BUGSModel,
    ::WithinGibbs{JuliaBUGS.HMCSampler},
    state;
    var_iterator=model.parameters,
)
    vi = state.varinfo
    for v in var_iterator
        ni = model.g[v]
        args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
        dist = _eval(ni.node_function_expr.args[2], args)

        transformed_original = ensure_vector(Bijectors.link(dist, vi[v]))

        mb_model = JuliaBUGS.MarkovBlanketBUGSModel(
            vi,
            ensure_vector(v),
            state.markov_blanket_cache[v],
            state.sorted_nodes_cache[v],
            model,
        )

        ad_mb_model = LogDensityProblemsAD.ADgradient(:ReverseDiff, mb_model)
        t, s = AbstractMCMC.step(
            rng,
            AbstractMCMC.LogDensityModel(ad_mb_model),
            HMC(0.1, 10); # TODO: use usr defined parameters
            n_adapts=1,
            initial_params=transformed_original, # TODO: can also save the state
        )

        sample_val = DynamicPPL.invlink_and_reconstruct(dist, t.z.θ)
        vi = DynamicPPL.setindex!!(vi, sample_val, v)
    end
    return vi
end

end
