struct BUGSModel <: AbstractPPL.AbstractProbabilisticProgram
    vars
    array_map
    var_types
    dep_graph
    sorted_nodes
    bijectors
    prior_types
    node_args
    node_functions
    link_functions
    partial_trace
    parameters
end

function BUGSModel(vars, array_map, var_types, dep_graph, node_args, node_functions, link_functions, data, inits)
    trace = Dict()
    parameters = []
    for var in keys(vars)
        var_types[var] == :logical && continue
        
        value = JuliaBUGS.eval(var, data)
        if !isnothing(value)
            trace[var] = value
            continue
        end

        push!(parameters, var)
        value = JuliaBUGS.eval(var, inits)
        isnothing(value) && error("$var is not initialized")
        trace[var] = value
    end

    sorted_nodes =  topological_sort_by_dfs(dep_graph)
    bijectors, prior_types = Dict(), Dict()
    for v_id in sorted_nodes
        var = vars(v_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            trace[var] = Base.invokelatest(node_functions[var], arguments...)
        else
            # TODO: for the same stochastic variable, node function can return different types of Distributions
            # as long as the support is the consistent, it is fine
            bijectors[var] = Bijectors.bijector(Base.invokelatest(node_functions[var], arguments...))
            prior_types[var] = typeof(Base.invokelatest(node_functions[var], arguments...))
        end
    end

    return BUGSModel(
        vars, array_map, var_types, dep_graph, sorted_nodes, bijectors, prior_types, node_args, node_functions, link_functions, trace, parameters
    )
end

function flatten(trace, parameters)
    return vcat([trace[var] for var in parameters]...)
end

function unflatten(trace, parameters, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = value
    end
    return trace
end

function transform_and_flatten(trace, parameters, bijectors)
    return vcat([bijectors[var](trace[var]) for var in parameters]...)
end

function untransform_and_unflatten(trace, parameters, bijectors, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = inv(bijectors[var])(value)
    end
    return trace
end

struct BUGSLogDensityProblem 
    m::BUGSModel
end

function (p::BUGSLogDensityProblem)(x)
    trace = untransform_and_unflatten(p.m.partial_trace, p.m.parameters, p.m.bijectors, x)
    return logjoint(p.m, trace)
end

function logjoint(m::BUGSModel, trace)
    vars, var_types, dep_graph, sorted_nodes, node_args, node_functions, link_functions = m.vars, m.var_types, m.dep_graph, m.sorted_nodes, m.node_args, m.node_functions, m.link_functions
    logdensity = 0.0
    for v_id in sorted_nodes
        var = vars(v_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            trace[var] = Base.invokelatest(node_functions[var], arguments...)
        else
            if haskey(link_functions, var)
                logdensity += logpdf(
                    Base.invokelatest(node_functions[var], arguments...),
                    eval(link_functions[var])(trace[var]),
                )
            else
                logdensity += logpdf(
                    Base.invokelatest(node_functions[var], arguments...), trace[var]
                )
            end
        end
    end
    return logdensity
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, params)
    return p(params)
end

function LogDensityProblems.dimension(p::BUGSLogDensityProblem)
    return length(flatten(p.m.trace, p.m.parameters))
end

function LogDensityProblems.capabilities(p::BUGSLogDensityProblem)
    if all((x) -> x <: ContinuousUnivariateDistribution, values(p.m.prior_types))
        return LogDensityProblems.LogDensityOrder{1}()
    else
        return LogDensityProblems.LogDensityOrder{0}()
    end
end
using LogDensityProblems
