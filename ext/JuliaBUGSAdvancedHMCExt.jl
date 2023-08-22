module JuliaBUGSAdvancedHMCExt

# The main purpose of this extension is to add `generated_quantities` to the final chains.
# So directly calling the AdvancedHMCMCMCChainsExt is not feasible.

using JuliaBUGS
using JuliaBUGS: AbstractBUGSModel, find_generated_vars, LogDensityContext, evaluate!!
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
    sampler::AdvancedHMC.AbstractHMCSampler,
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
    generated_vars = filter(l_var -> l_var in find_generated_vars(g), model.sorted_nodes)
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

    param_names = JuliaBUGS.param_names(model)
    return Chains(
        vals,
        vcat(param_names, Symbol.(generated_vars), tstat_names),
        (parameters=vcat(param_names, Symbol.(generated_vars)), internals=tstat_names);
        start=discard_initial + 1,
        thin=thinning,
    )
end

end
