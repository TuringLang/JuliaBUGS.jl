using Graphs
using AbstractPPL
using DensityInterface
using MacroTools
using Random

struct BUGSGraph <: AbstractPPL.AbstractProbabilisticProgram
    nodeenum::Dict{Symbol, Integer}
    reverse_nodeenum::Vector{Symbol}
    digraph::DiGraph
    sortednode::Vector{Integer}
    parents::Vector{Vector{Integer}}
    isobserve::BitVector
    observed_values::Dict{Integer, Real}
    nodefunc::Vector{Expr}
    nodefuncptr::Vector{Function}
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

    isobserve = BitVector(undef, numnodes)
    observed_values = Dict{Integer, Real}()
    nodefunc = Vector{Expr}(undef, numnodes)
    nodefuncptr = Vector{Function}(undef, numnodes)
    for k in keys(tograph)
        isobserve[nodeenum[k]] = tograph[k][3]
        if tograph[k][3]
            @assert !isempty(tograph[k][1])
            observed_values[nodeenum[k]] = tograph[k][1]
        end
        nodefunc[nodeenum[k]] = tograph[k][2] |> MacroTools.flatten |> MacroTools.resyntax
        nodefuncptr[nodeenum[k]] = eval(tograph[k][2])
    end

    return nodeenum, reverse_nodeenum, DAG, sortednode, parents, isobserve, observed_values, nodefunc, nodefuncptr
end

function BUGSGraph(tograph::Dict{Any, Any})
    nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, nodefuncptr = _BUGSGRAPH(tograph)
    return BUGSGraph(nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, nodefuncptr, Dict{Integer, Real}())
end

function BUGSGraph(tograph::Dict, inits::NamedTuple)
    nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, nodefuncptr = _BUGSGRAPH(tograph)
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
    return BUGSGraph(nodeenum, reverse_nodeenum, DAG, sortednode, parents, isoberve, observevalues, nodefunc, nodefuncptr, initializations)
end

struct Trace <: AbstractPPL.AbstractModelTrace
    value::Vector{Real}
    logp::Vector{Real}
end

"""
    getdistribution(g, node, value)

Return a Distribution.jl distribution.
"""
function getdistribution(g::BUGSGraph, node::Integer, value::Vector{Real}, delta::Dict=Dict())::Distributions.Distribution
    args = []
    for p in g.parents[node]
        if p in keys(delta)
            push!(args, delta[p])
        else
            push!(args, value[p])
        end
    end
    return (g.nodefuncptr[node])(args...)
end
getdistribution(g::BUGSGraph, node::Integer, trace::Trace) = getdistribution(g, node, trace.value)
getdistribution(g::BUGSGraph, node::Integer, trace::Trace, delta::Dict) = getdistribution(g, node, trace.value, delta)

"""
    parents(g, node)

Return the parents of the node.
"""
parents(g::BUGSGraph, node::Integer) = g.parents[node]

"""
    children(g, node)

Return the children of the node.
"""
children(g::BUGSGraph, node::Integer) = outneighbors(g.digraph, node)

"""
    markovblanket(g, node)

Return the Markov blanket of the node.
"""
function markovblanket(g::BUGSGraph, node::Integer)
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

function freevars(g::BUGSGraph, node::Integer)
    return push!(outneighbors(g.digraph, node), node)
end

"""
    numnodes(g)

Return the number of nodes.
"""
numnodes(g::BUGSGraph) = length(g.nodeenum)

"""
    getsortednodes(g)

Return all nodes in topological order.
"""
getsortednodes(g::BUGSGraph) = g.sortednode

"""
    nodename(g, node)

Return the name of the node given the node alias.
"""
nodename(g::BUGSGraph, node::Integer) = g.reverse_nodeenum[node]

"""
    nodealias(g, node)

Return the node alias given the node name.
"""
nodealias(g::BUGSGraph, node::Symbol) = g.nodeenum[node]

assumednodes(g::BUGSGraph) = [i for i in 1:numnodes(g) if !g.isobserve[i]]

getDAG(g::BUGSGraph) = g.digraph

function logdensityof(g::BUGSGraph, value::Vector{Real}, delta::Dict=Dict())
    logp = 0.0
    for node in g.sortednode
        if node in keys(delta)
            logp += logpdf(getdistribution(g, node, value, delta), delta[node])
        else
            logp += logpdf(getdistribution(g, node, value), value[node])
        end
    end
    return logp
end
logdensityof(g::BUGSGraph, trace::Trace, delta::Dict=Dict()) = logdensityof(g, trace.value, delta)

macro nn(expr)
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

function Random.rand(rng::Random.AbstractRNG, d::BUGSGraph) 
    value = Vector{Real}(undef, getnumnodes(d))
    for node in getsortednodes(d)
        if d.isobserve[node]
            value[node] = d.observed_values[node]
        else
            value[node] = rand(rng, getdistribution(d, node, value))
        end
    end
    return value
end

Random.rand(d::BUGSGraph) = rand(Random.GLOBAL_RNG, d)

# TODO: plot with Graphs.jl, ref: https://sisl.github.io/BayesNets.jl/dev/usage/