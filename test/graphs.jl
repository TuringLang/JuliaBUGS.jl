using JuliaBUGS
using JuliaBUGS: BUGSGraph, stochastic_neighbors, stochastic_inneighbors, stochastic_outneighbors
using Graphs, MetaGraphsNext

test_model = @bugsast begin
    a ~ dnorm(f, c)
    f = b - 1
    b ~ dnorm(0, 1)
    c ~ dnorm(0, 1)
    g = a * 2
    d ~ dnorm(g, 1)
    h = g + 2
    e ~ dnorm(h, 1)
end

model = compile(test_model, NamedTuple(), NamedTuple())
g = model.g

using GLMakie
using GraphMakie 

color = []
for node in labels(g)
    if g[node] isa JuliaBUGS.AuxiliaryNodeInfo
        push!(color, :blue)
    elseif g[node].node_type == JuliaBUGS.Stochastic
        if node in model.parameters
            push!(color, :green)
        else
            push!(color, :yellow)
        end
    else
        push!(color, :red)
    end
end

graphplot(
    g.graph; 
    ilabels=map(x->String(Symbol(x)), labels(g)),
    node_color=color
)


using TikzGraphs, TikzPictures
import TikzGraphs: plot

function plot(graph::BUGSGraph, parameters::Vector{VarName})
    color_dict = Dict{Int, String}()
    for (i, node) in enumerate(labels(graph))
        if node in parameters
            color_dict[i] = "fill=green!10"
        else
            color_dict[i] = "fill=yellow!10"
        end
    end

    TikzGraphs.plot(
        graph.graph, 
        map(x->String(Symbol(x)), labels(graph)), 
        node_style="draw, rounded corners, fill=blue!10", 
        node_styles=color_dict,
        edge_style="black"
    )
end