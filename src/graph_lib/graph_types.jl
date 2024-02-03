# struct NodeInfo end

function build_coarse_dependency_graph(state::CompileState)
    g = MetaGraph(
        DiGraph();
        label_type=Symbol,
        vertex_data_type=Union{Nothing, <:MetaGraph} # represented contracted node
        edge_data_type=Union{Statement,ForStatement},
        graph_data="Coarse Graph",
    )
    for statement in vcat(
        state.logical_statements,
        state.logical_for_statements,
        state.stochastic_statements,
        state.stochastic_for_statements,
    )
        lhs_var = statement.lhs isa Symbol ? statement.lhs : statement.lhs.args[1]
        add_vertex!(g, lhs_var, nothing)

        for rhs_var in statement.rhs_vars
            add_vertex!(g, rhs_var, nothing)
            add_edge!(g, rhs_var, lhs_var, statement)
        end
    end
    return g
end

function contract_until_dag(g::MetaGraph)

end

# the core is that for a graph contains loops, we can contract the cycle basis to a single node
# and then the graph becomes a DAG

# how many types of variables are there
# scalar, array variable, sub-graphs

# ! what do we want?
# efficiently compute the dependency structure
# the most accurate dependency requires building the graph
# but nice thing is that as long as the dependency contains all the variable in the MB, it is correct
# abstract interpretation?



g = build_coarse_dependency_graph(state)

# generate code to plot graph in pure text using print
for v in labels(g)
    println(v)
    for e in MetaGraphsNext.outneighbor_labels(g, v)
        println("  -> ", e)
    end
end

Graphs.is_cyclic(g.graph)

# the coarse graph is a possible graph via contraction 
Graphs.has_self_loops(g.graph)

# 