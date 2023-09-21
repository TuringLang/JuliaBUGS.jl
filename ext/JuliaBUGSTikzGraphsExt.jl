module JuliaBUGSTikzGraphsExt

using TikzGraphs
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function TikzGraphs.plot(m::JuliaBUGS.BUGSModel; kwargs...)
    return TikzGraphs.plot(m.g, m.parameters; kwargs...)
end

function TikzGraphs.plot(g::JuliaBUGS.BUGSGraph, parameters; kwargs...)
    color_dict = Dict{Int,String}()
    for (i, node) in enumerate(labels(g))
        if node in parameters
            color_dict[i] = "fill=green!10"
        else
            color_dict[i] = "fill=yellow!10"
        end
    end

    node_style = get(kwargs, :node_style, "draw, rounded corners, fill=blue!10")
    node_styles = get(kwargs, :node_styles, color_dict)
    edge_style = get(kwargs, :edge_style, "black")

    return TikzGraphs.plot(
        g.graph,
        map(x -> String(Symbol(x)), labels(g));
        node_style=node_style,
        node_styles=node_styles,
        edge_style=edge_style,
        kwargs...,
    )
end

end
