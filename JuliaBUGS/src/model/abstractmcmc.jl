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

    transition_env = merge(bugs_model.evaluation_env, transition)
    param_vars = if bugs_model.evaluation_mode isa UseAutoMarginalization
        bugs_model.marginalization_cache.continuous_model_parameters
    else
        model_parameters(bugs_model)
    end

    p = if params
        d = OrderedDict{String,Any}()
        for vn in param_vars
            value = AbstractPPL.getvalue(transition_env, vn)
            d[string(vn)] = value
        end
        [k => v for (k, v) in d]
    else
        nothing
    end

    s = if stats
        log_densities = if bugs_model.evaluation_mode isa UseAutoMarginalization
            _, lds = evaluate_with_marginalization_values!!(
                bugs_model, getparams(bugs_model, transition_env)
            )
            lds
        else
            model_with_env = BangBang.setproperty!!(bugs_model, :evaluation_env, transition_env)
            _, lds = evaluate_with_env!!(model_with_env; transformed=bugs_model.transformed)
            lds
        end
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
