module JuliaBUGSMCMCChainsExt

using JuliaBUGS
using JuliaBUGS: AbstractBUGSModel, find_generated_vars, evaluate!!
using JuliaBUGS.AbstractPPL
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.LogDensityProblemsAD
using AbstractMCMC
using MCMCChains: Chains

function JuliaBUGS.gen_chains(
    model::AbstractMCMC.LogDensityModel{<:JuliaBUGS.BUGSModel},
    samples,
    stats_names,
    stats_values;
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        model.logdensity,
        samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

function JuliaBUGS.gen_chains(
    model::AbstractMCMC.LogDensityModel{<:LogDensityProblemsAD.ADGradientWrapper},
    samples,
    stats_names,
    stats_values;
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    return JuliaBUGS.gen_chains(
        model.logdensity.ℓ,
        samples,
        stats_names,
        stats_values;
        discard_initial=discard_initial,
        thinning=thinning,
        kwargs...,
    )
end

# copied from DynamicPPL
varname_leaves(vn::VarName, ::Real) = [vn]
function varname_leaves(vn::VarName, val::AbstractArray{<:Union{Real,Missing}})
    return (
        VarName(vn, Accessors.IndexLens(Tuple(I)) ∘ getoptic(vn)) for
        I in CartesianIndices(val)
    )
end
function varname_leaves(vn::VarName, val::AbstractArray)
    return Iterators.flatten(
        varname_leaves(VarName(vn, Accessors.IndexLens(Tuple(I)) ∘ getoptic(vn)), val[I])
        for I in CartesianIndices(val)
    )
end
function varname_leaves(vn::VarName, val::NamedTuple)
    iter = Iterators.map(keys(val)) do sym
        optic = Accessors.PropertyLens{sym}()
        varname_leaves(VarName(vn, optic ∘ getoptic(vn)), optic(val))
    end
    return Iterators.flatten(iter)
end

function JuliaBUGS.gen_chains(
    model::JuliaBUGS.BUGSModel,
    samples,
    stats_names,
    stats_values;
    discard_initial=0,
    thinning=1,
    kwargs...,
)
    param_vars = model.parameters
    g = model.g

    generated_vars = find_generated_vars(g)
    generated_vars = [v for v in model.eval_cache.sorted_nodes if v in generated_vars] # keep the order

    param_vals = []
    generated_quantities = []
    for i in axes(samples)[1]
        evaluation_env = first(evaluate!!(model, samples[i]))
        push!(
            param_vals,
            [AbstractPPL.get(evaluation_env, param_var) for param_var in param_vars],
        )
        push!(
            generated_quantities,
            [
                AbstractPPL.get(evaluation_env, generated_var) for
                generated_var in generated_vars
            ],
        )
    end

    param_name_leaves = collect(
        Iterators.flatten([
            collect(varname_leaves(vn, param_vals[1][i])) for
            (i, vn) in enumerate(param_vars)
        ],),
    )
    generated_varname_leaves = collect(
        Iterators.flatten([
            collect(varname_leaves(vn, generated_quantities[1][i])) for
            (i, vn) in enumerate(generated_vars)
        ],),
    )

    # some of the values may be arrays
    flattened_param_vals = [collect(Iterators.flatten(p)) for p in param_vals]
    flattened_generated_quantities = [
        collect(Iterators.flatten(gq)) for gq in generated_quantities
    ]

    vals = [
        convert(
            Vector{Real},
            vcat(
                flattened_param_vals[i],
                flattened_generated_quantities[i],
                isempty(stats_values) ? [] : stats_values[i],
            ),
        ) for i in axes(samples)[1]
    ]

    @assert length(vals[1]) ==
        length(param_name_leaves) +
            length(generated_varname_leaves) +
            length(stats_names)

    return Chains(
        vals,
        vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves), stats_names),
        (
            parameters=vcat(Symbol.(param_name_leaves), Symbol.(generated_varname_leaves)),
            internals=stats_names,
        );
        start=discard_initial + 1,
        thin=thinning,
    )
end

end
