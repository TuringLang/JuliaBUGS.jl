function logjoint(model_def::Expr, data, initializations)
    vars, arrays_map, var_types = program!(CollectVariables(), model_def, data)
    vars, dep_graph = program!(DependencyGraph(vars, arrays_map), model_def, data)
    node_args, node_funcs = program!(NodeFunctions(), model_def, data, arrays_map)
    # evaled_node_funcs = Dict()
    # for (k, v) in node_funcs
    #     evaled_node_funcs[k] = eval(v)
    # end
    inits = inits_to_trace(initializations, data, var_types)
    return logdensity(dep_graph, vars, var_types, node_funcs, node_args, inits)
end

function inits_to_trace(inits, data, var_types)
    trace = Dict()
    for var in keys(var_types)
        if var_types[var] == :stochastic
            value = JuliaBUGS.eval(var, inits)
            isnothing(value) && (value = JuliaBUGS.eval(var, data))
            trace[var] = value
        end
    end
    return trace
end

function logdensity(dep_graph, vars, var_types, node_funcs, node_args, trace)
    sorted_node = filter(x -> vars.id_var_map[x] in keys(node_funcs), topological_sort_by_dfs(dep_graph))
    logical_trace = Dict()
    logdensity = 0.0
    for s in sorted_node
        v = vars.id_var_map[s]
        arguments = []
        for arg in node_args[v]
            if arg in keys(trace)
                push!(arguments, trace[arg])
            else
                push!(arguments, logical_trace[arg])
            end
        end
        if var_types[v] == :logical
            logical_trace[v] = Base.invokelatest(node_funcs[v], arguments...)
        else
            logdensity += logpdf(Base.invokelatest(node_funcs[v], arguments...), trace[v])
        end
    end
    return logdensity
end

