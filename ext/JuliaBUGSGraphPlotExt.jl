module JuliaBUGSGraphPlotExt

using GraphPlot
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphPlot.gplot(m::JuliaBUGS.BUGSModel; kwargs...)
    return GraphPlot.gplot(m.g, m.parameters; kwargs...)
end

function GraphPlot.gplot(g::JuliaBUGS.MetaGraph, parameters; kwargs...)
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

    nodelabel = get(kwargs, :nodelabel, map(x -> String(Symbol(x)), labels(g)))
    nodefillc = get(kwargs, :nodefillc, String.(colors))

    return gplot(g.graph; nodelabel=nodelabel, nodefillc=nodefillc, kwargs...)
end

end
