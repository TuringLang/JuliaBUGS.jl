module JuliaBUGSAdvancedHMCSampleExt

using AdvancedHMC
using JuliaBUGS
using JuliaBUGS: BUGSModel

function JuliaBUGS.Model._transition_params_and_stats(
    ::BUGSModel, ::AdvancedHMC.AbstractHMCSampler, transition::AdvancedHMC.Transition
)
    stats = merge((; lp=transition.z.ℓπ.value), AdvancedHMC.stat(transition))
    return transition.z.θ, stats
end

end
