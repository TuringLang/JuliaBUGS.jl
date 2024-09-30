using Pkg
Pkg.activate(; temp=true)
Pkg.add(["MetaGraphsNext", "GraphMakie", "Graphs", "GLMakie"])

using MetaGraphsNext
using Graphs
using GLMakie, GraphMakie

##

struct Node
    color::Int
end

function generate_three_color_metagraph(num_nodes::Int, p::Float64)
    g = MetaGraph(SimpleDiGraph(); label_type = Int, vertex_data_type = Node)

    for i in 1:num_nodes
        color = rand(1:3)
        add_vertex!(g, i, Node(color))
    end

    for i in 1:num_nodes
        for j in 1:num_nodes
            if i != j && rand() < p
                add_edge!(g, i, j)
            end
        end
    end

    return g
end

colors = [:red, :green, :blue]

g = generate_three_color_metagraph(10, 0.3)
while is_cyclic(g.graph)
    g = generate_three_color_metagraph(10, 0.3)
end

graphplot(g.graph; node_color = [color_map[g[label_for(g, v)]].color for v in vertices(g.graph)], ilabels = [label_for(g, v) for v in vertices(g.graph)])

t_closure = Graphs.transitiveclosure(g.graph)

graphplot(t_closure; node_color = [colors[g[v].color] for v in MetaGraphsNext.labels(g)])

function get_boundary_nodes(g::MetaGraph)
    t_closure = Graphs.transitiveclosure(g.graph)
    n = nv(g.graph)
    type_vector = zeros(Int, n)  # Stores types of vertices

    # Precompute types for all vertices
    for v_id in vertices(g.graph)
        _node = g[v_id]  # Assuming labels are the same as vertex IDs
        type_vector[v_id] = _node.color
    end

    vertices_of_type_2 = Int[]
    vertices_of_type_3 = Int[]

    for v_id in vertices(g.graph)
        _type = type_vector[v_id]
        if _type == 2 || _type == 3
            # Check if any descendants have type 1
            has_type1_descendant = any(type_vector[w] == 1 for w in outneighbors(t_closure, v_id))
            if !has_type1_descendant
                if _type == 2
                    push!(vertices_of_type_2, v_id)
                else
                    push!(vertices_of_type_3, v_id)
                end
            end
        end
    end

    return vertices_of_type_2, vertices_of_type_3
end

get_boundary_nodes(g)
