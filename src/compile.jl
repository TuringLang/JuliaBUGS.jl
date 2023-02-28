struct BUGSModel <: AbstractPPL.AbstractProbabilisticProgram
    vars
    array_map
    var_types
    dep_graph
    node_args
    node_functions
    link_functions
end

struct Trace <: AbstractPPL.AbstractModelTrace
    values
    logicals
    observations
    parameters
end

function Trace(m::BUGSModel, data, inits=nothing; force_init=false)
    values = Dict()
    vars, var_types, = m.vars, m.var_types
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

function LogDensityProblems.logdensity(model::BUGSModel, var)
    
    
end

using Bijectors
function get_bijectors(m::BUGSModel, t::Trace)
    trace = t.values
    vars, var_types, dep_graph, node_args, node_functions = m.vars, m.var_types, m.dep_graph, m.node_args, m.node_functions
    sorted_nodes =  topological_sort_by_dfs(m.dep_graph)
    bs = Dict()
    for v_id in sorted_nodes
        var = vars(v_id)
        arguments = [trace[arg] for arg in node_args[var]]
        if var_types[var] == :logical
            trace[var] = Base.invokelatest(node_functions[var], arguments...)
        else
            bs[var] = Bijectors.bijector(Base.invokelatest(node_functions[var], arguments...))
        end
    end
    return bs
end