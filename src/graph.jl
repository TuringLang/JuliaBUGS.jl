using Graphs

struct BUGSGraph
    nodeenum::Dict{Symbol, Int32}
    reverse_nodeenum::Dict{Int32, Symbol}
    digraph::DiGraph
    isoberve::Dict{Int32, Bool}
    observed_values::Dict{Int32, Real}
    nodefunc::Dict{Int32, Function}
    sortednode::Vector{Int32}
end

function BUGSGraph(tograph::Dict{Any, Any})
    nodeenum = Dict{Symbol, Int32}()
    for (i, k) in enumerate(keys(tograph))
        nodeenum[k] = i
    end
    reversenodeenum = Dict{Int32, Symbol}(v => k for (k, v) in nodeenum)

    parents = Dict{Symbol, Vector}()
    for k in keys(tograph)
        parents[k] = tograph[k][2].args[1].args
    end

    DAG = DiGraph(length(keys(tograph)))
    for k in keys(tograph)
        for p in parents[k]
            add_edge!(DAG, nodeenum[p], nodeenum[k])
        end
    end

    isoberve = Dict{Int32, Bool}()
    for k in keys(tograph)
        isoberve[nodeenum[k]] = tograph[k][3]
    end

    observevalues = Dict{Int32, Real}()
    for k in keys(tograph)
        if tograph[k][3] == :Observations
            observevalues[nodeenum[k]] = tograph[k][1]
        end
    end

    nodefunc = Dict{Int32, Function}()
    for k in keys(tograph)
        nodefunc[nodeenum[k]] = eval(tograph[k][2])
    end

    sortednode = topological_sort_by_dfs(DAG)

    return BUGSGraph(nodeenum, reversenodeenum, DAG, isoberve, observevalues, nodefunc, sortednode)
end


