module JuliaBUGSAdvancedHMCMCMCChainsExt

using AbstractMCMC
using AdvancedHMC
using JuliaBUGS
using JuliaBUGS.Model: BUGSModelLike
using MCMCChains

# AdvancedHMC ships its own `Chains` method that is more specific in the transition type,
# while the generic JuliaBUGS method is more specific in the model type. Neither wins, so
# this method resolves the ambiguity in favour of the JuliaBUGS one, which names variables
# after the model.
function AbstractMCMC.bundle_samples(
    ts::Vector{<:AdvancedHMC.Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:BUGSModelLike},
    sampler::AdvancedHMC.AbstractHMCSampler,
    state,
    chain_type::Type{MCMCChains.Chains};
    kwargs...,
)
    return JuliaBUGS.bundle_transitions(chain_type, logdensitymodel, ts, sampler; kwargs...)
end

end
