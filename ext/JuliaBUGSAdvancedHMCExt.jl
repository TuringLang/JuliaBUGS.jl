module JuliaBUGSAdvancedHMCExt

# The main purpose of this extension is to add `generated_quantities` to the final chains.
# So directly calling the AdvancedHMCMCMCChainsExt is not feasible.

using JuliaBUGS
using JuliaBUGS: AbstractBUGSModel, find_generated_vars, LogDensityContext, evaluate!!
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using JuliaBUGS.UnPack
using JuliaBUGS.DynamicPPL
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
    model::JuliaBUGS.BUGSModel=logdensitymodel.logdensity.ℓ, # MarkovBlanketCoveredBUGSModel not supported yet
    kwargs...,
)
    # return ts
    # Turn all the transitions into a vector-of-vectors.
    t = ts[1]
    tstat = merge((; lp=t.z.ℓπ.value), AdvancedHMC.stat(t))
    tstat_names = collect(keys(tstat))

    samples = [t.z.θ for t in ts]
    generated_vars = filter(
        l_var -> l_var in find_generated_vars(model.g), model.sorted_nodes
    )
    generate_quantities = Vector{Float64}[
        first(evaluate!!(model, LogDensityContext(), samples[i]))[generated_vars] for
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

    # getting a SimpleVarInfo of which keys are only the parameters
    param_vi = JuliaBUGS.get_params_varinfo(
        model, first(JuliaBUGS.evaluate!!(model, JuliaBUGS.LogDensityContext(), samples[1]))
    )
    param_name_leaves = vcat(
        [
            collect(DynamicPPL.varname_leaves(vn, param_vi.values[vn])) for
            vn in model.parameters
        ]...,
    )
    generated_varname_leaves = vcat(
        [
            collect(DynamicPPL.varname_leaves(vn, generate_quantities[1][i])) for
            (i, vn) in enumerate(generated_vars)
        ]...,
    )
    @assert length(vals[1]) ==
        length(param_name_leaves) +
            length(generated_varname_leaves) +
            length(tstat_names)

    return Chains(
        vals,
        vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves), tstat_names),
        (
            parameters=vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves)),
            internals=tstat_names,
        );
        start=discard_initial + 1,
        thin=thinning,
    )
end

end
