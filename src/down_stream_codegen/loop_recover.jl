using JuliaBUGS

struct Loop
    loop_vars::Vector{Symbol}
    bounds::Vector{Any}
    body::Vector{Any}
end

function recover_loops(g::JuliaBUGS.BUGSGraph, sorted_nodes)
    stmts = Any[]
    current_idx = 1
    
    while current_idx <= length(sorted_nodes)
        window, loop_vars, bounds = find_longest_matching_window(g, sorted_nodes, current_idx)
        
        if !isempty(window)
            push!(stmts, Loop(loop_vars, bounds, window))
            current_idx += length(window)
        else
            push!(stmts, sorted_nodes[current_idx])
            current_idx += 1
        end
    end
    
    return FuncBody(stmts)
end

function find_longest_matching_window(g::JuliaBUGS.BUGSGraph, sorted_nodes, start_idx)
    max_window_size = 10
    best_window = []
    best_loop_vars = Symbol[]
    best_bounds = Any[]
    
    # Iterate through possible window sizes
    for window_size in 1:min(max_window_size, length(sorted_nodes) - start_idx + 1)
        window = sorted_nodes[start_idx:start_idx+window_size-1]
        next_window = sorted_nodes[start_idx+window_size:start_idx+2*window_size-1]
        if match_window(g, window, next_window)
            loop_vars, bounds = extract_loop_info(g, window)
            # Update best window if current window is larger
            if length(window) > length(best_window)
                best_window = window
                best_loop_vars = loop_vars
                best_bounds = bounds
            end
        else
            # If window doesn't match, no need to check larger windows
            break
        end
    end
    
    return best_window, best_loop_vars, best_bounds
end

function match_window(g::JuliaBUGS.BUGSGraph, window, next_window)
    if isempty(window) || length(window) != length(next_window)
        return false
    end

    for i in eachindex(window)
        window_node = g[window[i]]
        next_window_node = g[next_window[i]]

        # Check if node functions match
        if window_node.node_function != next_window_node.node_function
            return false
        end

        if window_node.is_observed != next_window_node.is_observed
            return false
        end

        # Check if loop variables increase monotonically
        for (var, idx) in window_node.loop_vars
            if !haskey(next_window_node.loop_vars, var)
                return false
            end
            next_idx = next_window_node.loop_vars[var]
            if !(next_idx isa Integer) || !(idx isa Integer) || next_idx <= idx
                return false
            end
        end
        # Check if all loop variables in next_window_node are present in window_node
        for var in keys(next_window_node.loop_vars)
            if !haskey(window_node.loop_vars, var)
                return false
            end
        end
    end

    return true
end

function extract_loop_info(g::JuliaBUGS.BUGSGraph, window)
    loop_vars = Symbol[]
    bounds = Any[]
    if isempty(window)
        return loop_vars, bounds
    end
    
    ref_info = g[window[1]]
    last_info = g[window[end]]
    
    # Extract loop variables and their bounds
    for (var, start_idx) in ref_info.loop_vars
        end_idx = last_info.loop_vars[var]
        if typeof(start_idx) <: Integer && typeof(end_idx) <: Integer
            push!(loop_vars, var)
            push!(bounds, start_idx:end_idx)
        end
    end
    
    return loop_vars, bounds
end

# can this be done, maybe it is easier to do extra checks in compilation...
# basically says: if you write code this way, it is going to be good, otherwise, it is slow

# can we have a more coarse graph? like Pyro.plate


