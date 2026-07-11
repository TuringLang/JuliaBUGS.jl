module JuliaBUGSAdvancedMHSampleExt

using AdvancedMH
using JuliaBUGS
using JuliaBUGS: BUGSModel

function JuliaBUGS.Model._transition_params_and_stats(
    ::BUGSModel, ::AdvancedMH.MHSampler, transition::AdvancedMH.Transition
)
    params = transition.params isa AbstractArray ? transition.params : [transition.params]
    return params, (; lp=transition.lp)
end

end
