module JuliaBUGSGraphPlotExt

using GraphPlot
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphPlot.gplot(m::JuliaBUGS.BUGSModel)
    return GraphPlot.gplot(m.g, m.parameters)
end
function GraphPlot.gplot(g::JuliaBUGS.BUGSGraph, parameters)
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

    return gplot(
        g.graph; nodelabel=map(x -> String(Symbol(x)), labels(g)), nodefillc=String.(colors)
    )
end

end
