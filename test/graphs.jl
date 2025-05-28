using JuliaBUGS:
    stochastic_inneighbors, stochastic_neighbors, stochastic_outneighbors, markov_blanket

"""
    l
    │
    ↓
    c        b
    │        │
    ↓        ↓
    a ←──── f
    │
    ↓
    g
    ↙   ↘
    d       h
            │
            ↓
            e
            ↑
            i
"""

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
@test Set(Symbol.(markov_blanket(g, [a, l]))) == Set([:f, :b, :d, :e, :c, :h, :g, :i])

c = @varname c
@test Set(Symbol.(markov_blanket(model.g, c))) == Set([:l, :a, :b, :f])

cond_model = AbstractPPL.condition(model, setdiff(model.parameters, [c]))
# tests for MarkovBlanketBUGSModel constructor
@test cond_model.parameters == [c]
@test Set(Symbol.(cond_model.flattened_graph_node_data.sorted_nodes)) ==
    Set([:l, :a, :b, :f, :c])

decond_model = AbstractPPL.decondition(cond_model, [a, l])
@test Set(Symbol.(decond_model.parameters)) == Set([:a, :c, :l])
@test Set(Symbol.(decond_model.flattened_graph_node_data.sorted_nodes)) ==
    Set([:l, :b, :f, :a, :d, :e, :c, :h, :g, :i])

c_value = 4.0
mb_logp = begin
    logp = 0
    f = 2.0 - 1.0
    logp += logpdf(dnorm(f, c_value), 1.0) # a
    logp += logpdf(dnorm(0.0, 1.0), 2.0) # b
    logp += logpdf(dnorm(0.0, 1.0), -2.0) # l
    logp += logpdf(dnorm(-2.0, 1.0), c_value) # c
    logp
end

# order: b, l, c, a
@test mb_logp ≈ evaluate!!(cond_model, [c_value])[2] rtol = 1e-8

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
end ≈ evaluate!!(model, [-2.0, 4.0, 3.0, 2.0, 1.0, 4.0, 5.0])[2] atol = 1e-8

"""
mu[1]           mu[2]
   ╲            ╱
    ↘       ↙
     x[1:2]             z[1:2,1:2]
          ╲              ╱
           ↘         ↙
                 y
"""

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

## Tests for new functions below

using JuliaBUGS:
    _markov_blanket,
    dfs_find_stochastic_boundary_and_deterministic_variables_en_route,
    find_generated_quantities_variables

module GraphsTest
using JuliaBUGS: JuliaBUGS
using Graphs, MetaGraphsNext

export TestNode

struct TestNode
    node_type::Int
end

# overload the functions for testing purposes
function JuliaBUGS.is_model_parameter(
    g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int
)
    return g[v].node_type == 1
end
function JuliaBUGS.is_observation(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int)
    return g[v].node_type == 2
end
function JuliaBUGS.is_deterministic(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int)
    return g[v].node_type == 3
end
function JuliaBUGS.is_stochastic(g::MetaGraph{Int,<:SimpleDiGraph,Int,TestNode}, v::Int)
    return g[v].node_type != 3
end
end # module GraphsTest

@testset "find_generated_quantities_variables" begin
    using .GraphsTest

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

@testset "markov_blanket" begin
    using .GraphsTest

    """ Mermaid code for visualizing the test graph
    ```mermaid
    graph TD
        1((1: Parameter)) --> 2((2: Deterministic))
        1 --> 3((3: Parameter))
        2 --> 4((4: Deterministic))
        3 --> 5((5: Observation))
        4 --> 6((6: Deterministic))
        5 --> 6
        5 --> 7((7: Observation))
        6 --> 8((8: Parameter))
        7 --> 8

        classDef parameter fill:#f9f,stroke:#333,stroke-width:2px;
        classDef deterministic fill:#bfb,stroke:#333,stroke-width:2px;
        classDef observation fill:#bbf,stroke:#333,stroke-width:2px;

        class 1,3,8 parameter;
        class 2,4,6 deterministic;
        class 5,7 observation;
    ```
    """

    g = MetaGraph(SimpleDiGraph(); label_type=Int, vertex_data_type=TestNode)

    g[1] = TestNode(1)
    g[2] = TestNode(3)
    g[3] = TestNode(1)
    g[4] = TestNode(3)
    g[5] = TestNode(2)
    g[6] = TestNode(3)
    g[7] = TestNode(2)
    g[8] = TestNode(1)

    add_edge!(g, 1, 2)
    add_edge!(g, 1, 3)
    add_edge!(g, 2, 4)
    add_edge!(g, 3, 5)
    add_edge!(g, 4, 6)
    add_edge!(g, 5, 6)
    add_edge!(g, 5, 7)
    add_edge!(g, 6, 8)
    add_edge!(g, 7, 8)

    # Test single node Markov blanket
    @test dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, 1, MetaGraphsNext.outneighbor_labels
    ) == (Set([3, 8]), Set([4, 6, 2]))
    @test dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, 1, MetaGraphsNext.inneighbor_labels
    ) == (Set(), Set())
    @test _markov_blanket(g, 1) == Set(collect(1:8)) # should contains all the nodes

    @test dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, 5, MetaGraphsNext.outneighbor_labels
    ) == (Set([7, 8]), Set([6]))
    @test dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, 5, MetaGraphsNext.inneighbor_labels
    ) == (Set([3]), Set())
    @test _markov_blanket(g, 5) == Set([1, 2, 3, 4, 5, 6, 7, 8])

    @test _markov_blanket(g, 3) == Set([1, 3, 5])
    @test _markov_blanket(g, 7) == Set([1, 2, 4, 5, 6, 7, 8])
    @test _markov_blanket(g, 8) == Set([1, 2, 4, 5, 6, 7, 8])

    @test _markov_blanket(g, [1, 3]) == Set([1, 2, 3, 4, 5, 6, 7, 8])
    @test _markov_blanket(g, (3, 7)) == Set([1, 2, 3, 4, 5, 6, 7, 8])
end
