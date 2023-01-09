# The Graph Representation Compile Target

Directed Acyclic Graph (DAG) is classical representation of probabilistic models. 

## Node Data
```@docs
VertexInfo
```
Vertex store the following information:
- the name of the variable
- the parents of the variable
- the node function (see [Node Function](#node-function))
- whether the variable is data or not

## Node Function
The node function is a very flexible representation. 
The requirement for a node function is that when evaluate with the input arguments, it returns a `Distribution` object.
This may seems simple, but it can be very powerful.
For instance, a mixture model can be represented by a node function similar to
```julia
function node_f(t, μ_1, μ_2, σ_1, σ_2)
    if t >= 4
        return Normal(μ_1, σ_1)
    else
        return Normal(μ_2, σ_2)
    end
end
```

## Plotting
A good way to debug a model is plotting the Bayesian Network. 
We recommend using the `TikzGraphs` package to plot the Bayesian Network. 
The following code shows how to plot the Bayesian Network of the model in the previous section. 
Please note that the following code requires local latex environment to work. 
For more information regarding installation and more advanced usage of `TikzGraphs`, please refer to the [TikzGraphs.jl](https://github.com/JuliaTeX/TikzGraphs.jl).

```julia
using SymbolicPPL
using Graphs, MetaGraphsNext

# Compile model
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
```

Also plotting with [GraphRecipes.jl](https://github.com/JuliaPlots/GraphRecipes.jl) is also possible, but not recommended.
```julia
# Plot with GraphRecipes
# The plot may not
using Plots, GraphRecipes
graphplot(
    g.graph,
    names = map(x->label_for(g, x), vertices(g)),
    curves = false,
    method = :tree
)
```
