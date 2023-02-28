
struct Trace <: AbstractPPL.AbstractModelTrace
    values::Dict{Var, Any}
    logicals::Vector{Var}
    observations::Vector{Var}
    parameters::Vector{Var}
end

function Trace(vars, var_types, data, inits=nothing; force_init=false)
    values = Dict()
    logicals, parameters, observations = [], [], []
    for var in keys(vars)
        if var_types[var] == :logical
            push!(logicals, var)
            continue
        else
            value = JuliaBUGS.eval(var, data)
            if !isnothing(value)
                push!(observations, var)
                values[var] = value
                continue
            end
            push!(parameters, var)
            value = JuliaBUGS.eval(var, inits)
            if isnothing(value)
                @assert !force_init
                value = rand(size(var)...)
            end
            values[var] = value
        end
    end
    return Trace(values, logicals, observations, parameters)
end


struct BUGSModel <: AbstractPPL.AbstractProbabilisticProgram
    vars
    array_map
    var_types
    dep_graph
    bijectors
    prior_types
    node_args
    node_functions
    link_functions
    trace::Trace
end 

function BUGSModel(vars, array_map, var_types, dep_graph, node_args, node_functions, link_functions, data, inits)
    t = Trace(vars, var_types, data, inits)
    trace = t.values

    sorted_nodes =  topological_sort_by_dfs(m.dep_graph)
    bs, ds = Dict(), Dict()
    for v_id in sorted_nodes
        var = vars(v_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            trace[var] = Base.invokelatest(node_functions[var], arguments...)
        else
            bs[var] = Bijectors.bijector(Base.invokelatest(node_functions[var], arguments...))
            ds[var] = typeof(Base.invokelatest(node_functions[var], arguments...))
        end
    end
    return bs

    return BUGSModel(
        vars, array_map, var_types, dep_graph, bs, ds, node_args, node_functions, link_functions, t
    )
end

# TODO: add bijectors: during Trace creation with initializations and in `logdensity` computation 


# return a Vector of values of parameters
function flatten(t::Trace)
    return vcat([t.values[var] for var in t.parameters]...)
end

function unflatten(t::Trace, flattened_vales)
    values = t.values
    for (var, value) in zip(t.parameters, flattened_vales)
        values[var] = value
    end
    return Trace(values, t.logicals, t.observations, t.parameters)
end

function transform_and_flatten(t::Trace, bs)
    return vcat([bs[var](t.values[var]) for var in t.parameters]...)
end

function untransform_and_unflatten(t::Trace, flattened_vales, bs)
    values = t.values
    for (var, value) in zip(t.parameters, flattened_vales)
        values[var] = inv(bs[var])(value)
    end
    return Trace(values, t.logicals, t.observations, t.parameters)
end

struct BUGSLogDensityProblem 
    m::BUGSModel
    t::Trace
    bs::Dict
    ds::Dict
end

function (p::BUGSLogDensityProblem)(x)
    t = untransform_and_unflatten(p.t, x, p.bs)
    return logdensity(p.m, t)
end

function logdensity(m::BUGSModel, t)
    trace = t.values
    vars, var_types, dep_graph, node_args, node_functions, link_functions = m.vars, m.var_types, m.dep_graph, m.node_args, m.node_functions, m.link_functions
    sorted_nodes =  topological_sort_by_dfs(dep_graph)
    logdensity = 0.0
    for v_id in sorted_nodes
        var = vars(v_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            @assert !haskey(trace, var)
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
    return logdensity, trace
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, t)
    return p(t)
end

function LogDensityProblems.dimension(p::BUGSLogDensityProblem)
    return length(flatten(p.t))
end

function LogDensityProblems.capabilities(p::BUGSLogDensityProblem)
    if all(p.ds, (x) -> x isa ContinuousUnivariateDistribution)
        return LogDensityProblems.LogDensityOrder{1}()
    else
        return LogDensityProblems.LogDensityOrder{0}()
    end
end




# print the trace of two approach and compare them