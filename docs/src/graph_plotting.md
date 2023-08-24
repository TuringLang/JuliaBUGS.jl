# Plotting graphs

Plotting the graph can be very beneficial for debugging the model.

> **Note** Plate notation is not yet supported. Therefore, it's advisable for users to begin with a more streamlined model that contains fewer nodes, allowing for clearer visualization.

In Julia, we've set up standard plotting routines using various graphing libraries. You can visualize graphs with three different libraries by employing a common model, as detailed below:

```julia
model_def = @bugs begin
    a ~ dnorm(f, c)
    f = b - 1
    b ~ dnorm(0, 1)
    c ~ dnorm(l, 1)
    g = a * 2
    d ~ dnorm(g, 1)
    h = g + 2
    e ~ dnorm(h, i)
    i ~ dnorm(0, 1)
    l ~ dnorm(0, 1)
end

inits = Dict(
    :a => 1.0,
    :b => 2.0,
    :c => 3.0,
    :d => 4.0,
    :e => 5.0,

    # :f => 1.0,
    # :g => 2.0,
    # :h => 4.0,

    :i => 4.0,
    :l => -2.0,
)

model = compile(model_def, NamedTuple(), inits)
```

## [`TikzGraphs.jl`](https://github.com/JuliaTeX/TikzGraphs.jl).
```julia
using TikzGraphs
TikzGraphs.plot(model)
```
![TikzGraphs](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/docs/assets/tikz.svg)

## [`GraphPlot.jl`](https://github.com/JuliaGraphs/GraphPlot.jl)
```julia
using GraphPlot
gplot(model)
```
![GraphPlot](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/docs/graphplot.svg)

## [`GraphMakie.jl`](https://github.com/MakieOrg/GraphMakie.jl)
```julia
using GLMakie, GraphMakie
graphplot(model)
```
![GraphMakie](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/docs/makie.jpg)
