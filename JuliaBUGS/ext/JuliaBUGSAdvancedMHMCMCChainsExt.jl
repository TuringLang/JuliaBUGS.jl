module JuliaBUGSAdvancedMHMCMCChainsExt

using AbstractMCMC
using AdvancedMH
using JuliaBUGS
using JuliaBUGS.Model: BUGSModelLike
using MCMCChains

# Resolves the same ambiguity as `JuliaBUGSAdvancedHMCMCMCChainsExt`, for the three `Chains`
# methods that AdvancedMH defines. The two single-transition ones resolve to JuliaBUGS,
# which names variables after the model.
function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.AbstractTransition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{MCMCChains.Chains};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedMH.Transition{<:NamedTuple}},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AdvancedMH.MHSampler,
    state,
    chain_type::Type{MCMCChains.Chains};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

# `Ensemble` sampling stores one vector of walker transitions per iteration, which JuliaBUGS
# does not know how to read, so this one resolves the other way: AdvancedMH's own method is
# invoked explicitly, laying the walkers out as one chain each.
function AbstractMCMC.bundle_samples(
    ts::Vector{<:Vector{<:AdvancedMH.AbstractTransition}},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AdvancedMH.Ensemble,
    state,
    chain_type::Type{MCMCChains.Chains};
    kwargs...,
)
    return invoke(
        AbstractMCMC.bundle_samples,
        Tuple{
            Vector{<:Vector{<:AdvancedMH.AbstractTransition}},
            AdvancedMH.DensityModelOrLogDensityModel,
            AdvancedMH.Ensemble,
            Any,
            Type{MCMCChains.Chains},
        },
        ts,
        logdensitymodel,
        sampler,
        state,
        chain_type;
        kwargs...,
    )
end

end
