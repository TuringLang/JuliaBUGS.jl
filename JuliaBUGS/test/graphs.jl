using JuliaBUGS:
    markov_blanket,
    dfs_find_stochastic_boundary_and_deterministic_variables_en_route,
    find_generated_quantities_variables

# Helper module for testing graph functions with mock data
module GraphsTest
using JuliaBUGS: JuliaBUGS
using Graphs, MetaGraphsNext

export TestNode

struct TestNode
    node_type::Int  # 1: parameter, 2: observation, 3: deterministic
end

# Overload JuliaBUGS functions for testing purposes
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

@testset "Graph structure with BUGS models" begin
    @testset "Markov blanket computation" begin
        """
        Test graph structure:

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

        where:
        - a, b, c, d, e, i, l are stochastic nodes
        - f, g, h are deterministic nodes
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

        inits = (a=1.0, b=2.0, c=3.0, d=4.0, e=5.0, i=4.0, l=-2.0)
        model = compile(test_model, NamedTuple(), inits)
        g = model.g

        # Test Markov blanket for node 'a'
        # The Markov blanket of 'a' should include:
        # - Parents: b, c (via deterministic node f)
        # - Children: d, e (via deterministic nodes g and h)
        # - Co-parents of children: i (parent of e)
        # - All deterministic nodes on the paths: f, g, h
        a = @varname a
        @test Set(Symbol.(markov_blanket(g, a))) ==
            Set([:a, :f, :b, :d, :e, :c, :h, :g, :i])

        # Test Markov blanket for multiple nodes
        l = @varname l
        @test Set(Symbol.(markov_blanket(g, [a, l]))) ==
            Set([:a, :l, :f, :b, :d, :e, :c, :h, :g, :i])

        # Test Markov blanket for node 'c'
        # The Markov blanket of 'c' should include:
        # - Parents: l
        # - Children: a
        # - Co-parents of a: b (via f)
        # - Deterministic nodes: f
        c = @varname c
        @test Set(Symbol.(markov_blanket(model.g, c))) == Set([:c, :l, :a, :b, :f])
    end

    @testset "Array variables and auxiliary nodes" begin
        """
        Test graph with array variables:

        mu[1]           mu[2]
           ╲            ╱
            ↘       ↙
             x[1:2]             z[1:2,1:2]
                  ╲              ╱
                   ↘         ↙
                         y

        Note: Individual array elements like x[1], x[2], z[1,1] are handled as auxiliary nodes
        internally but are not exposed in the final graph structure.
        """
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

        # Verify that auxiliary nodes (z[1,1], x[1], x[2]) are created internally
        # but removed from the final graph, leaving only the main array variables
        @test Set(Symbol.(labels(model.g))) == Set([
            Symbol("mu[1]"), Symbol("x[1:2]"), Symbol("z[1:2, 1:2]"), Symbol("mu[2]"), :y
        ])
    end
end

@testset "Generated quantities detection" begin
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

    # Reference implementation using transitive closure
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
            10, 20, 100
        ],
        p in [0.1, 0.3]

        g = generate_random_dag(num_nodes, p)
        @test find_generated_quantities_variables(g) ==
            find_generated_quantities_variables_with_transitive_closure(g)
    end
end

@testset "Markov blanket helper functions" begin
    using .GraphsTest

    # Create a simple test graph
    # Graph structure:
    # 1 (param) → 2 (determ) → 4 (determ) → 6 (determ) → 8 (param)
    # ↓           ↓                          ↓
    # 3 (param) → 5 (obs) ────────────────→ 7 (obs)
    g = MetaGraph(SimpleDiGraph(); label_type=Int, vertex_data_type=TestNode)

    # Add nodes
    g[1] = TestNode(1)  # parameter
    g[2] = TestNode(3)  # deterministic
    g[3] = TestNode(1)  # parameter
    g[4] = TestNode(3)  # deterministic
    g[5] = TestNode(2)  # observation
    g[6] = TestNode(3)  # deterministic
    g[7] = TestNode(2)  # observation
    g[8] = TestNode(1)  # parameter

    # Add edges
    add_edge!(g, 1, 2)
    add_edge!(g, 1, 3)
    add_edge!(g, 2, 4)
    add_edge!(g, 3, 5)
    add_edge!(g, 4, 6)
    add_edge!(g, 5, 6)
    add_edge!(g, 5, 7)
    add_edge!(g, 6, 8)
    add_edge!(g, 7, 8)

    @testset "dfs_find_stochastic_boundary_and_deterministic_variables_en_route" begin
        # Test finding stochastic children from node 1
        stochastic_children, determ_en_route = dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
            g, 1, MetaGraphsNext.outneighbor_labels
        )
        @test stochastic_children == Set([3, 8])
        @test determ_en_route == Set([2, 4, 6])

        # Test finding stochastic parents from node 5
        stochastic_parents, determ_en_route = dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
            g, 5, MetaGraphsNext.inneighbor_labels
        )
        @test stochastic_parents == Set([3])
        @test determ_en_route == Set()
    end

    @testset "markov_blanket" begin
        # Node 1's Markov blanket includes all nodes due to the graph structure
        @test markov_blanket(g, 1) == Set(1:8)

        # Node 3's Markov blanket is smaller
        @test markov_blanket(g, 3) == Set([1, 3, 5])

        # Test multiple nodes
        @test markov_blanket(g, [1, 3]) == Set(1:8)
        @test markov_blanket(g, (3, 7)) == Set(1:8)
    end
end
