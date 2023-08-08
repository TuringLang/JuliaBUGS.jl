using JuliaBUGS
using JuliaBUGS:
    BUGSGraph,
    stochastic_neighbors,
    stochastic_inneighbors,
    stochastic_outneighbors,
    markov_blanket
using Graphs, MetaGraphsNext
using Test

test_model = @bugsast begin
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

model = compile(test_model, NamedTuple(), NamedTuple())
g = model.g

a = @varname a
l = @varname l
@test Set(Symbol.(stochastic_inneighbors(g, a))) == Set([:b, :c, :f])
@test Set(Symbol.(stochastic_outneighbors(g, a))) == Set([:d, :e, :h, :g])

@test Set(Symbol.(markov_blanket(g, a))) == Set([:f, :b, :a, :d, :e, :c, :h, :g, :i])
@test Set(Symbol.(markov_blanket(g, (a, l)))) ==
    Set([:f, :b, :a, :d, :e, :c, :h, :g, :i, :l])

# Test `MarkovBlanketCoveredModel`
# Idea: use conditioned `BUGSModel`