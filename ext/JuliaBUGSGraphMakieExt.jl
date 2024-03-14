module JuliaBUGSGraphMakieExt

using GLMakie
using GraphMakie
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphMakie.graphplot(m::JuliaBUGS.BUGSModel; kwargs...)
    return graphplot(m.g, m.parameters; kwargs...)
end
function GraphMakie.graphplot(g::JuliaBUGS.MetaGraph, parameters; kwargs...)
    colors = []
    for node in labels(g)
        if g[node].node_type == JuliaBUGS.Stochastic
            if node in parameters
                push!(colors, :green)
            else
                push!(colors, :yellow)
            end
        else
            push!(colors, :red)
        end
    end
    ilabels = get(kwargs, :ilabels, map(x -> String(Symbol(x)), labels(g)))
    node_color = get(kwargs, :node_color, colors)
    return graphplot(g.graph; ilabels=ilabels, node_color=node_color, kwargs...)
end

end
