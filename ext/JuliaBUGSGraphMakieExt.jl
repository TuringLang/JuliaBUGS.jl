module JuliaBUGSGraphMakieExt

using GLMakie
using GLMakie.ColorTypes: RGBA
using GraphMakie
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function GraphMakie.graphplot(m::JuliaBUGS.BUGSModel; kwargs...)
    return graphplot(m.g, m.graph_evaluation_data.sorted_parameters; kwargs...)
end
function GraphMakie.graphplot(g::JuliaBUGS.BUGSGraph, parameters; kwargs...)
    colors = []
    for node in labels(g)
        if g[node].is_stochastic
            if g[node].is_observed
                push!(colors, RGBA(0.5, 0.5, 0.5, 1.0))
            else
                push!(colors, RGBA(1, 1, 1, 1))
            end
        else
            push!(colors, RGBA(0.8, 0.9, 1.0, 1.0))
        end
    end
    ilabels = get(kwargs, :ilabels, map(x -> String(Symbol(x)), labels(g)))
    node_color = get(kwargs, :node_color, colors)

    return graphplot(
        g.graph; ilabels=ilabels, node_color=node_color, arrow_shift=:end, kwargs...
    )
end

end
