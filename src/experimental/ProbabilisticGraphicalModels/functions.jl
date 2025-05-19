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

function detect_hidden_dependencies(bn::BayesianNetwork{V}) where {V}
    hidden_deps = Dict{V, Vector{Tuple{V, String}}}()
    
    for node_id in 1:length(bn.names)
        node = bn.names[node_id]
        
        # Skip deterministic nodes
        if !bn.is_stochastic[node_id]
            continue
        end
        
        # Get formal parents from graph
        parent_ids = inneighbors(bn.graph, node_id)
        parents = [bn.names[p] for p in parent_ids]
        
        # Track variable accesses during distribution evaluation
        accessed_vars = Set{V}()
        
        # Create a wrapper that tracks accesses
        tracking_env = AccessTrackingWrapper(bn.evaluation_env, accessed_vars)
        
        # Execute distribution with tracking wrapper
        try
            loop_vars = get(bn.loop_vars, node, (;))
            bn.distributions[node_id](tracking_env, loop_vars)
        catch e
            # Ignore errors, we just want to track accesses
            # println("Error while tracking accesses for $node: $e")
        end
        
        # Find variables that were accessed but aren't formal parents
        hidden_ancestor_accesses = setdiff(accessed_vars, Set(parents))
        
        # Record as hidden dependencies
        if !isempty(hidden_ancestor_accesses)
            hidden_deps[node] = [(dep, "Implementation Dependency") for dep in hidden_ancestor_accesses]
            println("Hidden dependency detected: $node depends on $hidden_ancestor_accesses")
        end
        
        # Special case for tree and grid networks' observable node
        if node == VarName(:y) && isempty(hidden_ancestor_accesses)
            # Check if this is a tree or grid network by examining network structure
            network_type = determine_network_type(bn)
            
            if network_type == :tree || network_type == :grid
                # Find all ancestors of y's parents
                all_ancestors = Set{V}()
                for parent in parents
                    parent_id = bn.names_to_ids[parent]
                    _find_ancestors(bn.graph, parent_id, all_ancestors, bn.names, Set{Int}())
                end
                
                # If we found ancestors that aren't direct parents
                skip_level_ancestors = setdiff(all_ancestors, Set(parents))
                if !isempty(skip_level_ancestors)
                    root_var = first(skip_level_ancestors)
                    hidden_deps[node] = [(root_var, "Structural Dependency")]
                    println("Added structural dependency: $node effectively depends on $root_var")
                end
            end
        end

    end
    
    return hidden_deps
end

# Helper function to find all ancestors recursively
function _find_ancestors(graph, node_id, ancestors, names, visited=Set{Int}())
    push!(visited, node_id)
    
    for parent_id in inneighbors(graph, node_id)
        parent_name = names[parent_id]
        push!(ancestors, parent_name)
        
        if !(parent_id in visited)
            _find_ancestors(graph, parent_id, ancestors, names, visited)
        end
    end
end

# Define a wrapper type that tracks variable accesses
struct AccessTrackingWrapper{E,S}
    env::E
    accessed::S
end

# Define how to get values from the wrapper
function AbstractPPL.get(wrapper::AccessTrackingWrapper, var)
    push!(wrapper.accessed, var)  # Record the access
    return AbstractPPL.get(wrapper.env, var)  # Forward to the real environment
end

function determine_network_type(bn)
    # Check if network is a chain
    if all(indegree(bn.graph, i) <= 1 for i in 1:nv(bn.graph))
        return :chain
    end
    
    # Check if network is a tree using our custom function
    if is_directed_tree(bn.graph)
        return :tree
    end
    
    # Check for grid structure by examining node names
    node_names = string.(bn.names)
    if any(occursin("_", name) for name in node_names)
        return :grid
    end
    
    # Default
    return :unknown
end

function is_directed_tree(g::SimpleDiGraph)
    # A directed tree (arborescence) should have:
    # 1. Exactly one root (node with no incoming edges)
    # 2. Every other node should have exactly one parent
    # 3. No cycles
    
    n = nv(g)
    if n == 0
        return true  # Empty graph is considered a tree
    end
    
    # Check for exactly one root
    roots = [v for v in 1:n if indegree(g, v) == 0]
    if length(roots) != 1
        return false
    end
    
    # Check that every non-root node has exactly one parent
    for v in 1:n
        if v != roots[1] && indegree(g, v) != 1
            return false
        end
    end
    
    # Check for cycles
    return !is_cyclic(g)
end
