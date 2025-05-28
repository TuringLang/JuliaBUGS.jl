import AbstractPPL: condition, decondition

function condition(
    model::BUGSModel,
    d::Dict{<:VarName,<:Any},
    sorted_nodes=Nothing, # support cached sorted Markov blanket nodes
)
    new_evaluation_env = deepcopy(model.evaluation_env)
    for (p, value) in d
        new_evaluation_env = setindex!!(new_evaluation_env, value, p)
    end
    return condition(model, collect(keys(d)), new_evaluation_env; sorted_nodes=sorted_nodes)
end

function condition(
    model::BUGSModel,
    var_group::Vector{<:VarName},
    evaluation_env::NamedTuple=model.evaluation_env,
    sorted_nodes=Nothing,
)
    check_var_group(var_group, model)
    new_parameters = setdiff(model.parameters, var_group)

    sorted_blanket_with_vars = if sorted_nodes isa Nothing
        model.flattened_graph_node_data.sorted_nodes
    else
        filter(
            vn -> vn in union(markov_blanket(model.g, new_parameters), new_parameters),
            model.flattened_graph_node_data.sorted_nodes,
        )
    end

    g = copy(model.g)
    for vn in sorted_blanket_with_vars
        if vn in new_parameters
            continue
        end
        ni = g[vn]
        if ni.is_stochastic && !ni.is_observed
            ni = @set ni.is_observed = true
            g[vn] = ni
        end
    end

    new_model = BUGSModel(
        model, g, new_parameters, sorted_blanket_with_vars, evaluation_env
    )
    return BangBang.setproperty!!(new_model, :g, g)
end

function decondition(model::BUGSModel, var_group::Vector{<:VarName})
    check_var_group(var_group, model)
    base_model = model.base_model isa Nothing ? model : model.base_model

    new_parameters = [
        v for v in base_model.flattened_graph_node_data.sorted_nodes if
        v in union(model.parameters, var_group)
    ] # keep the order

    markov_blanket_with_vars = union(
        markov_blanket(base_model.g, new_parameters), new_parameters
    )
    sorted_blanket_with_vars = filter(
        vn -> vn in markov_blanket_with_vars,
        base_model.flattened_graph_node_data.sorted_nodes,
    )

    new_model = BUGSModel(
        model, model.g, new_parameters, sorted_blanket_with_vars, base_model.evaluation_env
    )
    evaluate_env, _ = evaluate!!(new_model)
    return BangBang.setproperty!!(new_model, :evaluation_env, evaluate_env)
end

function check_var_group(var_group::Vector{<:VarName}, model::BUGSModel)
    non_vars = filter(var -> var ∉ labels(model.g), var_group)
    logical_vars = filter(var -> !model.g[var].is_stochastic, var_group)
    isempty(non_vars) || error("Variables $(non_vars) are not in the model")
    return isempty(logical_vars) || error(
        "Variables $(logical_vars) are not stochastic variables, conditioning on them is not supported",
    )
end
