module JuliaBUGSAdvancedHMCExt

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
    VarName,
    AbstractBUGSModel
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.UnPack
using JuliaBUGS.DynamicPPL: settrans!!
using AbstractMCMC
using MCMCChains: Chains
using AdvancedHMC
using AdvancedHMC: Transition, stat

function AbstractMCMC.bundle_samples(
    ts::Vector{<:Transition},
    logdensitymodel::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    sampler::AbstractMCMC.AbstractSampler,
    state,
    chain_type::Type{Chains};
    discard_initial=0,
    thinning=1,
    model::AbstractBUGSModel=logdensitymodel.logdensity.ℓ,
    kwargs...,
)
    @unpack param_length, varinfo, parameters, g, sorted_nodes = model

    # Turn all the transitions into a vector-of-vectors.
    t = ts[1]
    tstat = merge((; lp=t.z.ℓπ.value), stat(t))
    tstat_names = collect(keys(tstat))

    samples = [t.z.θ for t in ts]
    generated_vars = filter(l_var -> l_var in find_logical_roots(g), model.sorted_nodes)
    model = settrans!!(model, true)
    generate_quantities = [
        evaluate!!(model, LogDensityContext(), samples[i])[generated_vars] for
        i in eachindex(ts)
    ]
    vals = [
        vcat(
            ts[i].z.θ,
            generate_quantities[i],
            ts[i].z.ℓπ.value,
            collect(values(AdvancedHMC.stat(ts[i]))),
        ) for i in eachindex(ts)
    ]

    param_names = Symbol.(model.parameters)
    generated_vars_names = Symbol.(generated_vars)
    return Chains(
        vals,
        vcat(param_names, generated_vars_names, tstat_names),
        (parameters=vcat(param_names, generated_vars_names), internals=tstat_names);
        start=discard_initial + 1,
        thin=thinning,
    )
end

end
