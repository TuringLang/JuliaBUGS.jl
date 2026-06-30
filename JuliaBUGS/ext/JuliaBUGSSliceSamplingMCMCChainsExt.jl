module JuliaBUGSSliceSamplingMCMCChainsExt

using AbstractMCMC
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using MCMCChains
using SliceSampling

include("slice_sampling_stats.jl")

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{MCMCChains.Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_mcmc_stats(ts)

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:SliceSampling.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::SliceSampling.AbstractSliceSampling,
    state,
    chain_type::Type{MCMCChains.Chains};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names, stats_values = _slice_mcmc_stats(ts)

    return JuliaBUGS.gen_chains(
        logdensitymodel,
        param_samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

end
