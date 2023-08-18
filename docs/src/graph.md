### Node Function
A node function for a stochastic variable is required to such that, when evaluate with the input arguments, returns a `Distribution` object that can be scored.
Because the input can be arbitrary, a general node function can be very powerful.
For instance, a mixture model can be represented by
```julia
function node_f(t, μ_1, μ_2, σ_1, σ_2)
    if t >= 4
        return Normal(μ_1, σ_1)
    else
        return Normal(μ_2, σ_2)
    end
end
```
where `t` is the input argument and `μ_1, μ_2, σ_1, σ_2` are the parameters of the mixture model.

### Plotting
A good way to debug a model is plotting the Bayesian Network. 
We recommend using the `TikzGraphs` package to plot the Bayesian Network. 
The following code shows how to plot the Bayesian Network of the model in the previous section. 
Please note that the following code requires local latex environment to work. 
For more information regarding installation and more advanced usage of `TikzGraphs`, please refer to the [TikzGraphs.jl](https://github.com/JuliaTeX/TikzGraphs.jl).

```julia
expr = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(a, b)
    d ~ dnorm(a - b, c)
end
g = compile(expr, (b=2.0, c=3.0), (a=1.0, d=4.0))

using TikzGraphs, TikzPictures
import TikzGraphs: plot
using Graphs, MetaGraphsNext
using AbstractPPL

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
```

## Providing observations for parameters of the model will break the dependencies
E.g.
```julia
model_def = @bugast begin
    a ~ Normal(0, 1)
    b ~ Normal(0, 1)
    c ~ Normal(a, b)
end

data = (a=1.0, b=2.0)
```
the generated graph in this case will not contain edges `a -> c` and `b -> c`. And node function of `c` will be `c ~ Normal(1.0, 2.0)`. Ancestral sampling in this model will not sample `a` and `b` and will only sample `c` from `Normal(1.0, 2.0)`.
This behavior suggests that the model is constructed with the model definition and **the data**. Given different data, the model constructed may have different behaviors.

## NodeInfo
Is `AuxiliaryNodeInfo` necessary, we can simplify the graph by contracting the auxiliary nodes into the main nodes.
The label is a `VarName` which serve as both identifier and a key to the global variable store.
The computation dynamic is: `node_args` stores variables required to evaluate the node function.
Then the value of the node is computed, and the value is stored in variable store, but `var_store[varname]`  