function logjoint(model_def::Expr, data, initializations)
    vars, arrays_map, var_types = program!(CollectVariables(), model_def, data)
    dep_graph = program!(DependencyGraph(vars, arrays_map), model_def, data)
    node_args, node_functions, link_functions = program!(NodeFunctions(arrays_map), model_def, data, arrays_map)
    trace = inits_to_trace(initializations, data, var_types)
    return logjoint(dep_graph, vars, var_types, node_functions, node_args, link_functions, trace)
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

function logjoint(data, initializations, vars, var_types, dep_graph, node_functions, node_args, link_functions)
    sorted_node = filter(
        x -> vars(x) in keys(node_functions), topological_sort_by_dfs(dep_graph)
    )

    trace = Dict()
    for node_id in sorted_node
        var = vars(node_id)
        var_types[var] == :logical && continue
        if var_types[var] == :assumption
            value = JuliaBUGS.eval(var, initializations)
            if isnothing(value)
                value = rand(size(var)...)
            end
        elseif var_types[var] == :observation
            value = JuliaBUGS.eval(var, data)
        end
        trace[var] = value
    end
    
    logdensity = 0.0
    for node_id in sorted_node
        var = vars(node_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            @assert !haskey(trace, var)
            trace[var] = Base.invokelatest(node_functions[var], arguments...)
        else
            if haskey(link_functions, var)
                logdensity += logpdf(Base.invokelatest(node_functions[var], arguments...), eval(link_functions[var])(trace[var]))
            else
                logdensity += logpdf(Base.invokelatest(node_functions[var], arguments...), trace[var])
            end
        end
    end
    return logdensity
end
