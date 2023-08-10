using JuliaBUGS
using JuliaBUGS:
    BUGSGraph,
    stochastic_neighbors,
    stochastic_inneighbors,
    stochastic_outneighbors,
    markov_blanket
using JuliaBUGS:
    MarkovBlanketCoveredBUGSModel, evaluate!!, DefaultContext, LogDensityContext
using JuliaBUGS.BUGSPrimitives
using Graphs, MetaGraphsNext
using Distributions
using Test

test_model = @bugs begin
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

# construct a SimpleVarInfo
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

model = compile(test_model, NamedTuple(), inits)

c = @varname c
markov_blanket(model.g, c)
@test Set(Symbol.(markov_blanket(model.g, c))) == Set([:l, :a, :b, :c, :f])

mb_model = MarkovBlanketCoveredBUGSModel(model, c)
@test begin
    logp = 0
    logp += logpdf(dnorm(1.0, 3.0), 1.0) # a
    logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
    logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
    logp += logpdf(dnorm(-2.0, 1.0), 3.0) # c
    logp
end == evaluate!!(mb_model, DefaultContext()).logp

# test LogDensityContext
@test begin
    logp = 0
    logp += logpdf(dnorm(1.0, 3.0), 1.0) # a, where f = 1.0
    logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
    logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
    logp += logpdf(dnorm(-2.0, 1.0), 3.0) # c
    logp += logpdf(dnorm(0.0, 1.0), 4.0) # i
    logp += logpdf(dnorm(2.0, 1.0), 4.0) # d, where g = 2.0
    logp += logpdf(dnorm(4.0, 4.0), 5.0) # e, where h = 4.0
    logp
end ≈ evaluate!!(model, LogDensityContext([4.0, 2.0, -2.0, 3.0, 1.0, 5.0, 4.0])).logp atol =
    1e-8
