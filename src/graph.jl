using Graphs
using Random
using MetaGraphsNext

struct VertexInfo
    sorted_inputs::Tuple
    is_data::Bool
    data::Union{Missing,Real}
    func_expr::Expr
    func_ptr::Function # a pointer to the eval-ed node_func
end

function to_metadigraph(pre_graph::Dict)
    g = MetaGraph(DiGraph(), Label = Symbol, VertexData = VertexInfo)
    
    for k in keys(pre_graph)
        vi = VertexInfo(
            Tuple(pre_graph[k][2].args[1].args), 
            pre_graph[k][3], 
            pre_graph[k][1],
            pre_graph[k][2],
            eval(pre_graph[k][2])
        )
        g[k] = vi
    end

    for k in keys(pre_graph)
        for p in g[k].sorted_inputs
            add_edge!(g, p, k, nothing) || error("Edge addition failed for $p -> $k.")
        end
    end

    return g
end

function process_initializations(inits::NamedTuple)
    initializations = Dict{Symbol, Real}()
    for (k, v) in pairs(inits)
        if v isa Array
            for i in CartesianIndices(v)
                ismissing(v[i]) && continue
                s = bugs_to_julia("$k") * "$(collect(Tuple(i)))"
                n = tosymbol(tosymbolic(Meta.parse(s)))
                initializations[n] = v[i]
            end
        else
            occursin("[", string(k)) && 
                error("Initializations of single elements of arrays not supported, initialize the whole array instead.")
            initializations[k] = v
        end
    end
    return initializations
end

"""
    getdistribution(g, node, value)

Return a Distribution.jl distribution.
"""
function getdistribution(g::MetaDiGraph, node::Symbol, value::Dict{Symbol, Real}, delta::Dict{Symbol, <:Real}=Dict{Symbol, Float64}())::Distributions.Distribution
    args = []
    for p in g[node].sorted_inputs
        if p in keys(delta)
            push!(args, delta[p])
        else
            push!(args, value[p])
        end
    end
    return (g[node].func_ptr)(args...)
end

function shownodefunc(g::MetaDiGraph, node::Symbol)
    f_expr = g[node].func_expr
    arguments = f_expr.args[1].args
    io = IOBuffer();
    for i in 1:length(arguments)
        print(io, arguments[i])
        if i < length(arguments)
            print(io, ", ")
        end
    end
    println("Parent Nodes: " * String(take!(io)))
    println("Node Function: " * string(f_expr.args[2]))
end
