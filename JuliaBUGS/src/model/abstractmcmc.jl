using AbstractMCMC: AbstractMCMC

function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModel},
    sampler::AbstractMCMC.AbstractSampler,
    transition::NamedTuple,
    state;
    params::Bool=true,
    stats::Bool=false,
    extras::Bool=false,
)
    bugs_model = model.logdensity
    gd = bugs_model.graph_evaluation_data

    param_vars = if bugs_model.evaluation_mode isa UseAutoMarginalization
        mc = bugs_model.marginalization_cache
        filter(gd.sorted_parameters) do vn
            idx = findfirst(==(vn), gd.sorted_nodes)
            idx !== nothing && mc.node_types[idx] == :continuous
        end
    else
        gd.sorted_parameters
    end

    p = if params
        d = OrderedDict{String,Any}()
        for vn in param_vars
            value = AbstractPPL.getvalue(transition, vn)
            d[string(vn)] = value
        end
        [k => v for (k, v) in d]
    else
        nothing
    end

    s = if stats
        model_with_env = BangBang.setproperty!!(bugs_model, :evaluation_env, transition)
        _, log_densities = evaluate_with_env!!(
            model_with_env; transformed=bugs_model.transformed
        )
        (lp=log_densities.tempered_logjoint,)
    else
        NamedTuple()
    end

    e = extras ? NamedTuple() : NamedTuple()

    return AbstractMCMC.ParamsWithStats(p, s, e)
end

function AbstractMCMC.ParamsWithStats(
    model::AbstractMCMC.LogDensityModel{<:BUGSModelWithGradient},
    sampler::AbstractMCMC.AbstractSampler,
    transition::NamedTuple,
    state;
    kwargs...,
)
    base_model = AbstractMCMC.LogDensityModel(model.logdensity.base_model)
    return AbstractMCMC.ParamsWithStats(base_model, sampler, transition, state; kwargs...)
end
