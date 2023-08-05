module JuliaBUGSGraphPlotExt

using GraphPlot
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphPlot.plot(g::JuliaBUGS.BUGSGraph, parameters)
    colors = []
    for node in labels(g)
        if g[node] isa JuliaBUGS.AuxiliaryNodeInfo
            push!(colors, :blue)
        elseif g[node].node_type == JuliaBUGS.Stochastic
            if node in parameters
                push!(colors, :green)
            else
                push!(colors, :yellow)
            end
        else
            push!(colors, :red)
        end
    end

    return gplot(
        g.graph; nodelabel=map(x -> String(Symbol(x)), labels(g)), nodefillc=String.(colors)
    )
end

end