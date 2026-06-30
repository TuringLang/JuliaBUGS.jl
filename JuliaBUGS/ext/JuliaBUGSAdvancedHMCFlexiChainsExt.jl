module JuliaBUGSAdvancedHMCFlexiChainsExt

using AbstractMCMC
using AdvancedHMC
using FlexiChains: FlexiChains
using JuliaBUGS
using JuliaBUGS: BUGSModelWithGradient
using JuliaBUGS.AbstractPPL: VarName

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{FlexiChains.VNChain};
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    # Extract parameter values and statistics from transitions
    param_samples = [t.z.θ for t in ts]

    # Collect statistic names and values
    # Include log probability and HMC-specific stats (step size, acceptance, etc.)
    stats_names = collect(keys(merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))))
    stats_values = [
        vcat(ts[i].z.ℓπ.value, collect(values(AdvancedHMC.stat(ts[i])))) for
        i in eachindex(ts)
    ]

    # Delegate to gen_chains for proper parameter naming from BUGSModel
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
