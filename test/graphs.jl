using SymbolicPPL
using Graphs, MetaGraphsNext

expr = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(a, b)
    d ~ dnorm(a - b, c)
end

g = compile(expr, NamedTuple(), :Graph)
g[:d]

# Plot with TikzGraphs
using TikzGraphs, TikzPictures
import TikzGraphs: plot

function plot(g)
    color_dict = Dict{Int, String}()
    for (i, node) in enumerate(vertices(g))
        if g[label_for(g, node)].is_data
            color_dict[i] = "fill=green!10"
        else
            color_dict[i] = "fill=yellow!10"
        end
    end

    TikzGraphs.plot(
        g.graph, 
        map(x->string(label_for(g, x)), vertices(g)), 
        node_style="draw, rounded corners, fill=blue!10", 
        node_styles=color_dict,
        edge_style="black"
    )
end

# Plot with GraphRecipes
using Plots, GraphRecipes
graphplot(
    g.graph,
    names = map(x->label_for(g, x), vertices(g)),
    curves = false,
    method = :tree
)
