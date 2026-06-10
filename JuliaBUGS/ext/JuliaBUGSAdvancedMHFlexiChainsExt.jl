module JuliaBUGSAdvancedMHFlexiChainsExt

using AbstractMCMC
using AdvancedMH
using FlexiChains: FlexiChain, VNChain
using JuliaBUGS
using JuliaBUGS: BUGSModel, BUGSModelWithGradient
using JuliaBUGS.AbstractPPL: VarName

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{VNChain};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Extract parameters and log densities
    param_samples = [t.params for t in ts]
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    # Delegate to gen_chains for proper parameter naming
    return JuliaBUGS.gen_chains(
        chain_type,
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
    ts::Vector{<:AdvancedMH.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{VNChain};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_samples = [t.params for t in ts]
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]

    return JuliaBUGS.gen_chains(
        chain_type,
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
