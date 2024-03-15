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

g = model.g

a = @varname a
l = @varname l
@test Set(Symbol.(stochastic_inneighbors(g, a))) == Set([:b, :c, :f])
@test Set(Symbol.(stochastic_outneighbors(g, a))) == Set([:d, :e, :h, :g])

@test Set(Symbol.(markov_blanket(g, a))) == Set([:f, :b, :d, :e, :c, :h, :g, :i])
@test Set(Symbol.(markov_blanket(g, (a, l)))) == Set([:f, :b, :d, :e, :c, :h, :g, :i])

c = @varname c
@test Set(Symbol.(markov_blanket(model.g, c))) == Set([:l, :a, :b, :f])

cond_model = AbstractPPL.condition(model, setdiff(model.parameters, [c]))
# tests for MarkovBlanketBUGSModel constructor
@test cond_model.parameters == [c]
@test Set(Symbol.(cond_model.sorted_nodes)) == Set([:l, :a, :b, :f, :c])

decond_model = AbstractPPL.decondition(cond_model, [a, l])
@test Set(Symbol.(decond_model.parameters)) == Set([:a, :c, :l])
@test Set(Symbol.(decond_model.sorted_nodes)) == Set([:i, :b, :f, :g, :h, :e, :d])

c_value = 4.0
mb_logp = begin
    logp = 0
    logp += logpdf(dnorm(1.0, c_value), 1.0) # a
    logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
    logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
    logp += logpdf(dnorm(-2.0, 1.0), c_value) # c
    logp
end

# order: b, l, c, a
@test mb_logp ≈ evaluate!!(cond_model, LogDensityContext(), [c_value])[2] rtol = 1e-8

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
end ≈ evaluate!!(model, LogDensityContext(), [4.0, 2.0, -2.0, 3.0, 1.0, 5.0, 4.0])[2] atol =
    1e-8

# AuxiliaryNodeInfo
test_model = @bugs begin
    x[1:2] ~ dmnorm(mu[:], sigma[:, :])
    for i in 1:2
        mu[i] ~ dnorm(0, 1)
    end
    z[1:2, 1:2] ~ dwish(R[:, :], 2)
    y ~ dnorm(x[1], x[2] + 1 + z[1, 1])
end

model = compile(
    test_model,
    Dict(:R => [200 0; 0 0.2], :sigma => [1.0E-6 0; 0 1.0E-6]),
    Dict(:x => [1.0, 2.0], :z => zeros(2, 2)),
)

# z[1,1], x[1], x[2] are auxiliary nodes created, and removed at the end
@test Set(Symbol.(labels(model.g))) ==
    Set([Symbol("mu[1]"), Symbol("x[1:2]"), Symbol("z[1:2,1:2]"), Symbol("mu[2]"), :y])



using JuliaBUGS
using MetaGraphsNext

(;model_def, data, inits) = JuliaBUGS.BUGSExamples.leuk;
(;model_def, data, inits) = JuliaBUGS.BUGSExamples.rats;

g = compile(model_def, data, inits[1])
@run compile(model_def, data, inits[1])

es = collect(edge_labels(g))
collect(labels(g))

d = Serialization.deserialize("/home/sunxd/JuliaBUGS.jl.worktrees/sunxd/profile_graph_creation/temp")


for k in es
    if k ∉ d
        println(k)
    end
end

d[1]

d[1] in es