module JuliaBUGSMCMCChainsExt

using JuliaBUGS
using JuliaBUGS:
    Logical,
    Stochastic,
    AuxiliaryNodeInfo,
    _eval,
    find_logical_roots,
    BUGSModel,
    LogDensityContext,
    evaluate!!,
    VarName
using JuliaBUGS.BUGSPrimitives
using MCMCChains
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.UnPack
using JuliaBUGS.DynamicPPL: settrans!!

function MCMCChains.Chains(
    samples::AbstractVector{<:AbstractVector{<:Union{Missing,Real}}},
    m::LogDensityProblemsAD.ADGradientWrapper,
)
    return MCMCChains.Chains(samples::AbstractVector{<:AbstractVector}, m.ℓ)
end
function MCMCChains.Chains(
    samples::AbstractVector{<:AbstractVector{<:Union{Missing,Real}}}, model::BUGSModel
)
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model
    num_spls = length(samples)
    @assert length(samples[1]) == model.param_length "Number of parameters in samples does not match number of parameters in model"

    logical_roots = filter(l_var -> l_var in find_logical_roots(g), model.sorted_nodes)
    all_vars = VarName[model.parameters..., logical_roots...]
    model = settrans!!(model, true)
    values = [
        evaluate!!(model, LogDensityContext(), samples[i])[all_vars] for i in 1:num_spls
    ]

    return Chains(values, Symbol.(all_vars))
end

end