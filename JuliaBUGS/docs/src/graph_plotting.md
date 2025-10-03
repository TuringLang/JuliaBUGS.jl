# Plotting graphs

Plotting the graphical model can be very beneficial for debugging the model.

!!! note "Plate notation is not yet supported"
    Users are advised to begin with a model that contains fewer nodes, so that the graph is easier to visualize.

We have set up standard plotting routines with [`GraphMakie.jl`](https://github.com/MakieOrg/GraphMakie.jl) and [`GraphPlot.jl`](https://github.com/JuliaGraphs/GraphPlot.jl), via package extensions.

Observed nodes are colored in gray, unobserved nodes are colored in white, and deterministic nodes are colored in light blue.

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

data = (
    e = 5.0,
)

inits = (
    a = 1.0,
    b = 2.0,
    c = 3.0,
    d = 4.0,
    i = 4.0,
    l = -2.0,
)

model = compile(model_def, data, inits)
```

## [`GraphPlot.jl`](https://github.com/JuliaGraphs/GraphPlot.jl)

```julia
using GraphPlot
gplot(model)
```

![GraphPlot](https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/JuliaBUGS/docs/assets/graphplot.svg)

## [`GraphMakie.jl`](https://github.com/MakieOrg/GraphMakie.jl)

```julia
using GLMakie, GraphMakie
graphplot(model)
```

![GraphMakie](https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/JuliaBUGS/docs/assets/makie.png)
