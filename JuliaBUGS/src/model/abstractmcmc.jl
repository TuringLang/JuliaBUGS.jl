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

    param_vars = Model._active_parameter_vars(bugs_model)

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
