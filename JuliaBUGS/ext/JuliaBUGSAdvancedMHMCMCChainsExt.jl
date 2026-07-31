module JuliaBUGSAdvancedMHMCMCChainsExt

using AbstractMCMC
using AdvancedMH
using JuliaBUGS
using JuliaBUGS.Model: BUGSModelLike
using MCMCChains

# Resolves the same ambiguity as `JuliaBUGSAdvancedHMCMCMCChainsExt`, for the two `Chains`
# methods that AdvancedMH defines.
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

end
