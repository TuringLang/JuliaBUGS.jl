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
    tstat = merge((; lp=ts[1].z.ℓπ.value), AdvancedHMC.stat(ts[1]))
    tstat_names = collect(keys(tstat))

    samples = [t.z.θ for t in ts]

    param_vars = model.parameters

    generated_vars = find_generated_vars(model.g)
    generated_vars = [v for v in model.sorted_nodes if v in generated_vars] # keep the order

    param_vals = []
    generated_quantities = []
    for i in eachindex(ts)
        vi = first(evaluate!!(model, LogDensityContext(), samples[i]))
        push!(param_vals, [vi[param_var] for param_var in param_vars])
        push!(generated_quantities, [vi[generated_var] for generated_var in generated_vars])
    end

    param_name_leaves = vcat(
        [
            collect(DynamicPPL.varname_leaves(vn, param_vals[1][i])) for
            (i, vn) in enumerate(param_vars)
        ]...,
    )
    generated_varname_leaves = vcat(
        [
            collect(DynamicPPL.varname_leaves(vn, generated_quantities[1][i])) for
            (i, vn) in enumerate(generated_vars)
        ]...,
    )

    # some of the values may be arrays
    flattened_param_vals = [vcat(p...) for p in param_vals]
    flattened_generated_quantities = [vcat(gq...) for gq in generated_quantities]
    vals = [
        convert(
            Vector{Real},
            vcat(
                flattened_param_vals[i],
                flattened_generated_quantities[i],
                ts[i].z.ℓπ.value,
                collect(values(AdvancedHMC.stat(ts[i]))),
            ),
        ) for i in eachindex(ts)
    ]

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
