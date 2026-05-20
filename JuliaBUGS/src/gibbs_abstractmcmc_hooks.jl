function AbstractMCMC.condition(
    model::BUGSModel, target_varnames::AbstractVector{<:VarName}, global_values::NamedTuple
)
    model = BangBang.setproperty!!(model, :evaluation_env, global_values)
    vars_to_condition = setdiff(
        model.graph_evaluation_data.sorted_parameters, target_varnames
    )
    return JuliaBUGS.condition(model, vars_to_condition)
end

function AbstractMCMC.condition(model::BUGSModel, ::AbstractVector{<:VarName}, ::Nothing)
    return model
end

function AbstractMCMC._init_global_values(
    ::BUGSModel, ::AbstractVector{<:VarName}, cond_model::BUGSModel, ::Any
)
    return cond_model.evaluation_env
end

function AbstractMCMC._update_global_values(
    ::BUGSModel,
    global_values::NamedTuple,
    target_vars::AbstractVector{<:VarName},
    cond_model::BUGSModel,
    new_params::AbstractVector{<:Real},
)
    updated_model = JuliaBUGS.setparams!!(cond_model, new_params)
    new_env = updated_model.evaluation_env
    result = global_values
    for vn in target_vars
        sym = AbstractPPL.getsym(vn)
        if haskey(new_env, sym)
            result = BangBang.setindex!!(result, new_env[sym], vn)
        end
    end
    return result
end

function AbstractMCMC.getparams(model::BUGSModel, state)
    env = state isa NamedTuple ? state : model.evaluation_env
    return JuliaBUGS.getparams(model, env)
end

function AbstractMCMC.setparams!!(model::BUGSModel, state, params::AbstractVector{<:Real})
    return JuliaBUGS.setparams!!(model, params).evaluation_env
end

AbstractMCMC._build_gibbs_transition(global_values::NamedTuple) = global_values
