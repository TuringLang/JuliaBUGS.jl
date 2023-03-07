struct BUGSLogDensityProblem
    """ map variables to their ids """
    vars::Bijection{Var,Int}
    """ identity array variables as logical or stochastic """
    var_types
    dep_graph::SimpleDiGraph
    sorted_nodes
    """ map variables to their transformation to unconstrained space """
    bijectors
    """ map variables to type of their prior distribution """
    prior_types
    node_args
    node_functions
    link_functions
    init_trace
    """ list of stochastic variables that can't be resolved from data """
    parameters
    compiled_tape
    gradient_cfg
    all_results
end

function BUGSLogDensityProblem(
    vars, var_types, dep_graph, node_args, node_functions, link_functions, data, inits
)
    init_trace = Dict()
    parameters = []
    for var in keys(vars)
        var_types[var] == :logical && continue

        value = JuliaBUGS.eval(var, data)
        if !isnothing(value)
            init_trace[var] = value
            continue
        end

        push!(parameters, var)
        value = JuliaBUGS.eval(var, inits)
        if isnothing(value)
            value = rand(size(var)...)
            println(
                "No initial value provided for $var, initialized to $value by random sampling.",
            )
        end
        init_trace[var] = value
    end

    sorted_nodes = map(vars, topological_sort_by_dfs(dep_graph))
    bijectors, prior_types = Dict(), Dict()
    for var in sorted_nodes
        arguments = [init_trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            init_trace[var] = node_functions[var](arguments...)
        else
            # assume that: if a node function can return different types of Distributions, they would have the same support 
            bijectors[var] = Bijectors.bijector(node_functions[var](arguments...))
            prior_types[var] = typeof(node_functions[var](arguments...))
        end
    end

    return BUGSLogDensityProblem(
        vars,
        var_types,
        dep_graph,
        sorted_nodes,
        bijectors,
        prior_types,
        node_args,
        node_functions,
        link_functions,
        init_trace,
        parameters,
        nothing,
        nothing,
        nothing,
    )
end

function gen_init_params(p::BUGSLogDensityProblem, transform=true)
    if transform
        return transform_and_flatten(p.init_trace, p.parameters, p.bijectors)
    else
        return flatten(p.init_trace, p.parameters)
    end
end

function flatten(trace, parameters)
    return vcat([deepcopy(trace[var]) for var in parameters]...)
end

function unflatten(trace, parameters, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = value
    end
    return trace
end

function transform_and_flatten(trace, parameters, bijectors)
    return vcat([bijectors[var](deepcopy(trace[var])) for var in parameters]...)
end

function unflatten_and_untransform(trace, parameters, bijectors, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = inv(bijectors[var])(value)
    end
    return trace
end

function (p::BUGSLogDensityProblem)(x, transform=true)
    if transform
        trace = unflatten_and_untransform(p.init_trace, p.parameters, p.bijectors, x)
    else
        trace = unflatten(p.init_trace, p.parameters, x)
    end
    return logjoint(p, trace)
end

function logjoint(p::BUGSLogDensityProblem, trace)
    var_types, sorted_nodes, node_args, node_functions, link_functions, = p.var_types,
    p.sorted_nodes, p.node_args, p.node_functions,
    p.link_functions

    logjoint = 0.0
    for var in sorted_nodes
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            trace[var] = node_functions[var](arguments...)
        else
            if haskey(link_functions, var)
                logjoint += logpdf(
                    node_functions[var](arguments...), eval(link_functions[var])(trace[var])
                )
            else
                logjoint += logpdf(node_functions[var](arguments...), trace[var])
            end
        end
    end
    return logjoint
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, x)
    return p(x)
end

function LogDensityProblems.dimension(p::BUGSLogDensityProblem)
    return length(gen_init_params(p))
end

function LogDensityProblems.logdensity_and_gradient(p::BUGSLogDensityProblem, x)
    ReverseDiff.gradient!(p.all_results, p.compiled_tape, x)
    return ReverseDiff.DiffResults.value(p.all_results),
    ReverseDiff.DiffResults.gradient(p.all_results)
end

function LogDensityProblems.capabilities(p::BUGSLogDensityProblem)
    if all((x) -> x <: ContinuousDistribution, values(p.prior_types))
        return LogDensityProblems.LogDensityOrder{1}()
    else
        return LogDensityProblems.LogDensityOrder{0}()
    end
end

function transform_samples(p::BUGSLogDensityProblem, flattened_vales::Vector)
    trace = deepcopy(p.init_trace)
    for (var, value) in zip(p.parameters, flattened_vales)
        trace[var] = inv(p.bijectors[var])(value)
    end
    for var in p.sorted_nodes
        arguments = [trace[arg] for arg in p.node_args[var]]
        if p.var_types[var] == :logical
            trace[var] = p.node_functions[var](arguments...)
        else
            continue
        end
    end
    return trace
end
