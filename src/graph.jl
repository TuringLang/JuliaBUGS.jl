using Graphs
using AbstractPPL
using DensityInterface
using MacroTools

struct BUGSGraph <: AbstractPPL.AbstractProbabilisticProgram
    nodeenum::Dict{Symbol, Integer}
    reverse_nodeenum::Vector{Symbol}
    digraph::DiGraph
    sortednode::Vector{Integer}
    parents::Vector{Vector{Integer}}
    isoberve::BitVector
    observed_values::Dict{Integer, Real}
    nodefunc::Vector{Expr}
    initializations::Dict{Integer, Real}
end

function _BUGSGRAPH(tograph::Dict)
    numnodes = length(keys(tograph))
    
    nodeenum = Dict{Symbol, Integer}()
    for (i, k) in enumerate(keys(tograph))
        nodeenum[k] = i
    end

    reverse_nodeenum = Vector{Symbol}(undef, numnodes)
    for (k, v) in nodeenum
        reverse_nodeenum[v] = k
    end

    parents = Vector{Vector{Integer}}(undef, numnodes)
    for k in keys(tograph)
        pa = tograph[k][2].args[1].args
        if isempty(pa)
            parents[nodeenum[k]] = []
        else
            parents[nodeenum[k]] = [nodeenum[p] for p in pa]
        end
    end

    DAG = DiGraph(length(keys(tograph)))
    for k in keys(tograph)
        node = nodeenum[k]
        for p in parents[node]
            add_edge!(DAG, p, node)
        end
    end
    sortednode = topological_sort_by_dfs(DAG)

    isoberve = BitVector(undef, numnodes)
    observevalues = Dict{Integer, Real}()
    nodefunc = Vector{Expr}(undef, numnodes)
    for k in keys(tograph)
        isoberve[nodeenum[k]] = tograph[k][3]
        if tograph[k][3]
            @assert !isempty(tograph[k][1])
            observevalues[nodeenum[k]] = tograph[k][1]
        end
        nodefunc[nodeenum[k]] = tograph[k][2]
    end

    return nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc
end

function BUGSGraph(tograph::Dict{Any, Any})
    nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc = _BUGSGRAPH(tograph)
    return BUGSGraph(nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, Dict{Integer, Real}())
end

function BUGSGraph(tograph::Dict, inits::NamedTuple)
    nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc = _BUGSGRAPH(tograph)
    initializations = Dict{Integer, Real}()
    for (k, v) in pairs(inits)
        if v isa Array
            for i in CartesianIndices(v)
                ismissing(v[i]) && continue
                s = bugs_to_julia("$k") * "$(collect(Tuple(i)))"
                n = tosymbol(tosymbolic(Meta.parse(s)))
                initializations[nodeenum[n]] = v[i]
            end
        else
            occursin("[", string(k)) && 
                error("initializations of single elements of arrays not supported, please initialize the whole array.")
            initializations[nodeenum[k]] = v
        end
    end
    return BUGSGraph(nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, initializations)
end

struct Trace <: AbstractPPL.AbstractModelTrace
    value::Vector{Real}
    logp::Vector{Real}
end

"""
    getdistribution(g, node, value)

Return a Distribution.jl distribution.
"""
function getdistribution(g::BUGSGraph, node::Integer)::Function
    return function (value::Vector{Real})
        eval(g.nodefunc[node])([value[p] for p in g.parents[node]]...)
    end
end
getdistribution(g::BUGSGraph, node::Integer, trace::Trace) = getdistribution(g, node, trace.value)
getdistribution(g::BUGSGraph, node::Integer, value::Vector{Real}) = getdistribution(g, node)(value)

"""
    getparents(g, node)

Return the parents of the node.
"""
getparents(g::BUGSGraph, node::Integer) = g.parents[node]

"""
    getchildren(g, node)

Return the children of the node.
"""
getchidren(g::BUGSGraph, node::Integer) = outneighbors(g.digraph, node)


"""
    getmarkovblanket(g, node)

Return the Markov blanket of the node.
"""
function getmarkovblanket(g::BUGSGraph, node::Integer)
    mb = Set{Integer}()
    push!(mb, node)
    for p in inneighbors(g.digraph, node)
        push!(mb, p)
    end
    for p in outneighbors(g.digraph, node)
        push!(mb, p)
        for c in inneighbors(g.digraph, p)
            push!(mb, c)
        end
    end
    return collect(mb)
end

"""
    getnumnodes(g)

Return the number of nodes.
"""
getnumnodes(g::BUGSGraph) = length(g.nodeenum)

"""
    getsortednodes(g)

Return all nodes in topological order.
"""
getsortednodes(g::BUGSGraph) = g.sortednode

"""
    getnodename(g, node)

Return the name of the node given the node alias.
"""
getnodename(g::BUGSGraph, node::Integer) = g.reverse_nodeenum[node]

"""
    getnodeenum(g, node)

Return the node alias given the node name.
"""
getnodeenum(g::BUGSGraph, node::Symbol) = g.nodeenum[node]

getDAG(g::BUGSGraph) = g.digraph

macro nodename(expr)
    name = tosymbol(tosymbolic(expr))
    return :($(QuoteNode(name)))
end

function shownodefunc(g::BUGSGraph, node::Integer)
    f_expr = g.nodefunc[node]
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

