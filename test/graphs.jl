using JuliaBUGS:
    stochastic_inneighbors,
    stochastic_neighbors,
    stochastic_outneighbors,
    markov_blanket,
    find_generated_quantities_variables

@testset "find_generated_quantities_variables" begin
    struct TestNode
        id::Int
    end

    JuliaBUGS.is_model_parameter(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int) =
        g[v].id == 1
    JuliaBUGS.is_observation(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int) =
        g[v].id == 2
    JuliaBUGS.is_deterministic(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int) =
        g[v].id == 3

    function generate_random_dag(num_nodes::Int, p::Float64=0.3)
        graph = SimpleGraph(num_nodes)
        for i in 1:num_nodes
            for j in 1:num_nodes
                if i != j && rand() < p
                    add_edge!(graph, i, j)
                end
            end
        end

        graph = Graphs.random_orientation_dag(graph) # ensure the random graph is a DAG
        vertices_description = [i => TestNode(rand(1:3)) for i in 1:nv(graph)]
        edges_description = [Tuple(e) => nothing for e in Graphs.edges(graph)]
        return MetaGraph(graph, vertices_description, edges_description)
    end

    # `transitiveclosure` has time complexity O(|E|⋅|V|), not fit for large graphs
    # but easy to implement and understand, here we use it for reference
    function find_generated_quantities_variables_with_transitive_closure(
        g::MetaGraph{Int,<:SimpleDiGraph,Label,VertexData}
    ) where {Label,VertexData}
        _transitive_closure = Graphs.transitiveclosure(g.graph)
        generated_quantities_variables = Set{Label}()
        for v_id in vertices(g.graph)
            if !JuliaBUGS.is_observation(g, v_id)
                if all(
                    !Base.Fix1(JuliaBUGS.is_observation, g),
                    outneighbors(_transitive_closure, v_id),
                )
                    push!(generated_quantities_variables, MetaGraphsNext.label_for(g, v_id))
                end
            end
        end

        return generated_quantities_variables
    end

    @testset "random DAG with $num_nodes nodes and $p probability of edge" for num_nodes in
                                                                               [
            10, 20, 100, 500, 1000
        ],
        p in [0.1, 0.3, 0.5]

        g = generate_random_dag(num_nodes, p)
        @test find_generated_quantities_variables(g) ==
            find_generated_quantities_variables_with_transitive_closure(g)
    end
end

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
inits = (
    a=1.0,
    b=2.0,
    c=3.0,
    d=4.0,
    e=5.0,

    # f = 1.0,
    # g = 2.0,
    # h = 4.0,

    i=4.0,
    l=-2.0,
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
@test mb_logp ≈ evaluate!!(cond_model, JuliaBUGS.LogDensityContext(), [c_value])[2] rtol =
    1e-8

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
end ≈ evaluate!!(
    model, JuliaBUGS.LogDensityContext(), [-2.0, 4.0, 3.0, 2.0, 1.0, 4.0, 5.0]
)[2] atol = 1e-8

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
    (R=[200 0; 0 0.2], sigma=[1.0E-6 0; 0 1.0E-6]),
    (x=[1.0, 2.0], z=zeros(2, 2)),
)

# z[1,1], x[1], x[2] are auxiliary nodes created, and removed at the end
@test Set(Symbol.(labels(model.g))) ==
    Set([Symbol("mu[1]"), Symbol("x[1:2]"), Symbol("z[1:2, 1:2]"), Symbol("mu[2]"), :y])
