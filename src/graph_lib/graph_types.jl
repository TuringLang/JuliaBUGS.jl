function build_coarse_dep_graph(state::CompileState)
    g = MetaGraph(DiGraph(); label_type=Any, edge_data_type=Any)

    for (i, stmt) in enumerate(all_statements(state))
        lhs_var_sym = stmt.lhs isa Symbol ? stmt.lhs : stmt.lhs.args[1]
        lhs_label = (lhs_var_sym, i)
        add_vertex!(g, lhs_label)

        for rhs in stmt.rhs_vars
            if rhs == lhs_var_sym
                # variable rhs is used in its own definition, may have self-loop
                # or may not: x[1:3] depdens on x[4:6], but we can't be sure
                return nothing
            end
            rhs_label = (rhs, nothing)
            add_vertex!(g, rhs_label)
            add_edge!(g, rhs_label, lhs_label, stmt)
        end
    end

    # now contract the vertices
    ts = Dict()
    for l in labels(g)
        ts[first(l)] = get(ts, first(l), Any[l])
    end

    g_new = MetaGraph(DiGraph(); label_type=Symbol, edge_data_type=Union{Statement, ForStatement})

    # merge all the vertices with the same sym for label
    for (symbol, labels_list) in ts
        add_vertex!(g_new, symbol)
        for label in labels_list
            for in_neighbor_label in inneighbor_labels(g, label)
                edge_data = getindex(g, in_neighbor_label, label)
                add_edge!(g_new, in_neighbor_label[1], symbol, edge_data)
            end
            for out_neighbor_label in outneighbor_labels(g, label)
                edge_data = getindex(g, label, out_neighbor_label)
                add_edge!(g_new, symbol, out_neighbor_label[1], edge_data)
            end
        end
    end

    return g_new
end
