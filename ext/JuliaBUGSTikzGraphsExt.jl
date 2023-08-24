module JuliaBUGSTikzGraphsExt

using TikzGraphs
using JuliaBUGS
using JuliaBUGS.MetaGraphsNext

function TikzGraphs.plot(m::JuliaBUGS.BUGSModel)
    return TikzGraphs.plot(m.g, m.parameters)
end
function TikzGraphs.plot(graph::JuliaBUGS.BUGSGraph, parameters)
    color_dict = Dict{Int,String}()
    for (i, node) in enumerate(labels(graph))
        if node in parameters
            color_dict[i] = "fill=green!10"
        else
            color_dict[i] = "fill=yellow!10"
        end
    end

    return TikzGraphs.plot(
        graph.graph,
        map(x -> String(Symbol(x)), labels(graph));
        node_style="draw, rounded corners, fill=blue!10",
        node_styles=color_dict,
        edge_style="black",
    )
end

end
