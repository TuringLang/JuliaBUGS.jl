module JuliaBUGSGraphPlotExt

using GraphPlot
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphPlot.gplot(m::JuliaBUGS.BUGSModel; kwargs...)
    return GraphPlot.gplot(m.g, m.parameters; kwargs...)
end

function GraphPlot.gplot(g::JuliaBUGS.BUGSGraph, parameters; kwargs...)
    colors = String[]
    for node in labels(g)
        if g[node].is_stochastic
            if g[node].is_observed
                push!(colors, "gray")
            else
                push!(colors, "white")
            end
        else
            push!(colors, "lightblue")
        end
    end

    nodelabel = get(kwargs, :nodelabel, map(x -> String(Symbol(x)), labels(g)))
    nodefillc = get(kwargs, :nodefillc, colors)

    return gplot(g.graph; nodelabel=nodelabel, nodefillc=nodefillc, kwargs...)
end

end
