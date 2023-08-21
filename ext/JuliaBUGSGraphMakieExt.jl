module JuliaBUGSGraphMakieExt

using GLMakie
using GraphMakie
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphMakie.graphplot(g::JuliaBUGS.BUGSGraph, parameters)
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
    return graphplot(
        g.graph; ilabels=map(x -> String(Symbol(x)), labels(g)), node_color=colors
    )
end

end
