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
