module JuliaBUGSAdvancedMHExt

using JuliaBUGS
using JuliaBUGS: BUGSModel, find_generated_vars, LogDensityContext, evaluate!!
import JuliaBUGS: gibbs_internal
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.UnPack
using JuliaBUGS.DynamicPPL
using JuliaBUGS: Random, Bijectors
using AbstractMCMC
using AdvancedMH
using MCMCChains: Chains

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.AbstractTransition},
    logdensitymodel::Union{
        AbstractMCMC.LogDensityModel{JuliaBUGS.BUGSModel},
        AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    },
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        logdensitymodel,
        [t.params for t in ts],
        [:lp],
        [t.lp for t in ts];
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function JuliaBUGS.gibbs_internal(
    rng::Random.AbstractRNG, cond_model::BUGSModel, sampler::AdvancedMH.MHSampler
)
    vi = cond_model.varinfo
    transformed_original = Real[]
    for v in cond_model.parameters
        ni = model.g[v]
        args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
        dist = _eval(ni.node_function_expr.args[2], args)

        transformed_original = vcat(transformed_original, Bijectors.link(dist, vi[v]))
    end

    ad_cond_model = LogDensityProblemsAD.ADgradient(:ReverseDiff, cond_model)
    t, s = AbstractMCMC.step(
        rng,
        AbstractMCMC.LogDensityModel(ad_cond_model),
        sampler;
        n_adapts=0,
        initial_params=transformed_original,
    )

    pos = 1
    for v in cond_model.parameters
        ni = model.g[v]
        args = (; (getsym(arg) => vi[arg] for arg in ni.node_args)...)
        dist = _eval(ni.node_function_expr.args[2], args)

        sample_val = DynamicPPL.invlink_and_reconstruct(
            dist, t.params[pos:(pos + length(dist) - 1)]
        )
        vi = DynamicPPL.setindex!!(vi, sample_val, v)
    end
    return vi
end

end
