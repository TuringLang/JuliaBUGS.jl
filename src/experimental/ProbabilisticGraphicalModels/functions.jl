"""
    ancestral_sampling(bn::BayesianNetwork{V}) where {V}

Perform ancestral sampling on a Bayesian network to generate one sample from the joint distribution.
"""
function ancestral_sampling(bn::BayesianNetwork{V}) where {V}
    ordered_vertices = Graphs.topological_sort_by_dfs(bn.graph)
    samples = Dict{V,Any}()

    for vertex_id in ordered_vertices
        vertex_name = bn.names[vertex_id]
        if bn.is_observed[vertex_id]
            samples[vertex_name] = bn.values[vertex_name]
            continue
        end
        if bn.is_stochastic[vertex_id]
            dist_idx = findfirst(id -> id == vertex_id, bn.stochastic_ids)
            samples[vertex_name] = rand(bn.distributions[dist_idx])
        else
            # deterministic node
            parent_ids = Graphs.inneighbors(bn.graph, vertex_id)
            parent_values = [samples[bn.names[pid]] for pid in parent_ids]
            func_idx = findfirst(id -> id == vertex_id, bn.deterministic_ids)
            samples[vertex_name] = bn.deterministic_functions[func_idx](parent_values...)
        end
    end

    return samples
end

"""
    is_conditionally_independent(bn::BayesianNetwork, X::Vector{V}, Y::Vector{V}, Z::Vector{V}) where {V}

Test whether sets of variables X and Y are conditionally independent given set Z in a Bayesian Network using the Bayes Ball algorithm.
"""
function is_conditionally_independent(
    bn::BayesianNetwork{V}, X::Vector{V}, Y::Vector{V}, Z::Vector{V}
) where {V}
    isempty(X) && throw(ArgumentError("X cannot be empty"))
    isempty(Y) && throw(ArgumentError("Y cannot be empty"))

    x_ids = Set([bn.names_to_ids[x] for x in X])
    y_ids = Set([bn.names_to_ids[y] for y in Y])
    z_ids = Set([bn.names_to_ids[z] for z in Z])

    # Check if any variable in X or Y is in Z
    if !isempty(intersect(x_ids, z_ids)) || !isempty(intersect(y_ids, z_ids))
        return true
    end

    # Add observed variables to conditioning set
    for (id, is_obs) in enumerate(bn.is_observed)
        if is_obs
            push!(z_ids, id)
        end
    end

    # Track visited nodes and their directions
    n_vertices = nv(bn.graph)
    visited_up = falses(n_vertices)   # Visited going up (from child to parent)
    visited_down = falses(n_vertices) # Visited going down (from parent to child)

    # Queue entries are (node_id, going_up)
    queue = Tuple{Int,Bool}[]

    # Start from all X nodes
    for x_id in x_ids
        push!(queue, (x_id, true))   # Try going up
        push!(queue, (x_id, false))  # Try going down
    end

    while !isempty(queue)
        current_id, going_up = popfirst!(queue)

        # Skip if we've visited this node in this direction
        if (going_up && visited_up[current_id]) || (!going_up && visited_down[current_id])
            continue
        end

        # Mark as visited in current direction
        if going_up
            visited_up[current_id] = true
        else
            visited_down[current_id] = true
        end

        # If we reached a Y node, path is active
        if current_id in y_ids
            return false
        end

        is_conditioned = current_id in z_ids
        parents = inneighbors(bn.graph, current_id)
        children = outneighbors(bn.graph, current_id)

        if is_conditioned
            # If conditioned:
            # - In a chain/fork: blocks the path
            # - In a collider or descendant of collider: allows going up to parents
            if length(parents) > 1 || !isempty(children)  # Is collider or has children
                for parent in parents
                    push!(queue, (parent, true))  # Can only go up to parents
                end
            end
        else
            # If not conditioned:
            if going_up
                # Going up: can visit parents
                for parent in parents
                    push!(queue, (parent, true))
                end
            else
                # Going down: can visit children
                for child in children
                    push!(queue, (child, false))
                end
            end

            # At starting nodes (X), we can go both up and down
            if current_id in x_ids
                if going_up
                    for child in children
                        push!(queue, (child, false))
                    end
                else
                    for parent in parents
                        push!(queue, (parent, true))
                    end
                end
            end
        end
    end

    return true
end

# Single variable version with Z
function is_conditionally_independent(
    bn::BayesianNetwork{V}, X::V, Y::V, Z::Vector{V}
) where {V}
    return is_conditionally_independent(bn, [X], [Y], Z)
end
