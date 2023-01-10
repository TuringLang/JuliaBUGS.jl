"""
    VertexInfo

VertexInfo is a struct that holds the information for each node in the BUGS graph.
"""
struct VertexInfo
    variable_name::Symbol
    sorted_inputs::Tuple
    is_data::Bool
    data::Union{Missing,Real}
    f_expr::Expr
    f::Function
end

"""
    BUGSGraph

BUGSGraph is synonymous with MetaGraphNext.MetaDiGraph with [`VertexInfo`](@ref) vertex type.
"""
const BUGSGraph = MetaGraph{<:Any,Symbol,<:SimpleDiGraph,<:VertexInfo}

function tograph(pre_graph::Dict)
    g = MetaGraph(DiGraph(); Label=Symbol, VertexData=VertexInfo)

    for k in keys(pre_graph)
        vi = VertexInfo(
            k,
            Tuple(pre_graph[k][2].args[1].args),
            pre_graph[k][3],
            pre_graph[k][1],
            pre_graph[k][2],
            eval(pre_graph[k][2]),
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

"""
    getdistribution(g, node, value)

Return a Distribution.jl distribution.
"""
function getdistribution(
    g::BUGSGraph, node::Symbol, value::Dict{Symbol,Any}, delta=Dict{Symbol,Any}()
)::Distributions.Distribution
    args = []
    for p in g[node].sorted_inputs
        if p in keys(delta)
            push!(args, delta[p])
        else
            push!(args, value[p])
        end
    end
    return (g[node].f)(args...)
end

function Base.show(io::IO, vinfo::VertexInfo)
    vinfo = deepcopy(vinfo)
    f_expr = vinfo.f_expr
    arguments = f_expr.args[1].args
    _io = IOBuffer()
    for i in 1:length(arguments)
        print(_io, arguments[i])
        if i < length(arguments)
            print(_io, ", ")
        end
    end
    d_expr = f_expr.args[2].args[1]

    println(io, "Variable Name: " * string(vinfo.variable_name))
    println(io, "Variable Type: " * (vinfo.is_data ? "Observation" : "Assumption"))
    vinfo.is_data && println(io, "Data: " * string(vinfo.data))
    println(io, "Parent Nodes: " * String(take!(_io)))
    print(io, "Node Function: ")
    return Base.show(io, d_expr)
end

"""
    dry_run(g)

Return the distribution types and values of the random variables via ancestral sampling.
"""
dry_run(g::BUGSGraph) = dry_run(g, (x -> label_for(g, x)).(topological_sort_by_dfs(g)))
function dry_run(g::BUGSGraph, sorted_nodes::Vector{Symbol})
    value = Dict{Symbol,Any}()
    dist_types = Dict{Any,Any}()
    for node in sorted_nodes
        if g[node].is_data
            value[node] = g[node].data
            dist_types[node] = typeof(getdistribution(g, node, value))
        else
            dist = getdistribution(g, node, value)
            value[node] = rand(dist)
            dist_types[node] = typeof(dist)
        end
    end

    return dist_types, value
end
