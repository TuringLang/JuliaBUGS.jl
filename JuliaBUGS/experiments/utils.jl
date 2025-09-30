using LogDensityProblems
using JuliaBUGS
using JuliaBUGS: compile
using AbstractPPL
using MetaGraphsNext
using Random
using LogExpFunctions

const JModel = JuliaBUGS.Model

"""
    compile_autmarg(model_def, data; transformed=true)

Compile a BUGS model, set transformed mode, and UseAutoMarginalization.
Returns the model and a zero vector of appropriate dimension.
"""
function compile_autmarg(model_def, data; transformed=true)
    m = compile(model_def, data)
    m = JModel.settrans(m, transformed)
    m = JModel.set_evaluation_mode(m, JModel.UseAutoMarginalization())
    if !(m.evaluation_mode isa JModel.UseAutoMarginalization)
        error(
            "Auto-marginalization mode was not activated (got $(typeof(m.evaluation_mode))). " *
            "Ensure the model can precompute marginalization caches before running experiments.",
        )
    end
    D = LogDensityProblems.dimension(m)
    return m, zeros(D)
end

"""
    build_interleaved_order(model)

For models with paired latent/observations like HMMs or mixture models where
names contain `z[i]` and `y[i]`, return an order that keeps non (z,y) nodes first
and then interleaves `z[i], y[i]` by ascending i. Falls back to `sorted_nodes`
when names are not present.
"""
function build_interleaved_order(model)
    gd = model.graph_evaluation_data
    z_idxs = Dict{Int,Int}()
    y_idxs = Dict{Int,Int}()
    other = Int[]
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0; z_idxs[i] = j; else; push!(other, j); end
        elseif startswith(s, "y[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0; y_idxs[i] = j; else; push!(other, j); end
        else
            push!(other, j)
        end
    end
    order = copy(other)
    if !isempty(z_idxs)
        for i in sort(collect(keys(z_idxs)))
            zi = z_idxs[i]
            push!(order, zi)
            yi = get(y_idxs, i, 0)
            if yi != 0; push!(order, yi); end
        end
    end
    return order
end

"""
    prepare_minimal_cache_keys(model, order)

Wrapper around `JuliaBUGS.Model._precompute_minimal_cache_keys` returning a Dict.
"""
function prepare_minimal_cache_keys(model, order::AbstractVector{<:Integer})
    return JModel._precompute_minimal_cache_keys(model, collect(order))
end

"""
    build_fhmm_interleaved_order(model)

For Factorial HMMs with names like `z[c,t]` and `y[t]`, return an order that
keeps non (z,y) nodes first and then, for t=1:T, lists `z[1,t], z[2,t], …, z[C,t], y[t]`.
Falls back to `sorted_nodes` when names are not present.
"""
function build_fhmm_interleaved_order(model)
    gd = model.graph_evaluation_data
    # Collect indices for discrete variables only (z[c,t])
    z_idxs = Dict{Tuple{Int,Int},Int}()  # (c,t) -> node idx
    max_c, max_t = 0, 0
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            # Extract indices inside brackets, e.g., "c,t"
            inner = replace(s[3:end-1], " " => "")
            parts = split(inner, ',')
            if length(parts) == 2
                c = try parse(Int, parts[1]) catch; -1 end
                t = try parse(Int, parts[2]) catch; -1 end
                if c > 0 && t > 0
                    z_idxs[(c, t)] = j
                    max_c = max(max_c, c)
                    max_t = max(max_t, t)
                end
            end
        end
    end
    # Build discrete-first interleaved-by-time order: for each time, z[1,t],...,z[C,t]
    disc_order = Int[]
    for t in 1:max_t
        for c in 1:max_c
            idx = get(z_idxs, (c, t), 0)
            if idx != 0
                push!(disc_order, idx)
            end
        end
    end
    # Lift to full evaluation order (places emissions y[t] when their discrete parents are ready)
    return build_eval_order_from_discrete_order(model, disc_order)
end

"""
    build_fhmm_states_first_order(model)

For FHMMs, return an order that lists all `z[c,t]` in increasing t and c first,
then all `y[t]`. This demonstrates poor ordering (frontier explosion) while
preserving topological constraints across time.
"""
function build_fhmm_states_first_order(model)
    gd = model.graph_evaluation_data
    z_idxs = Dict{Tuple{Int,Int},Int}()
    max_c, max_t = 0, 0
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            inner = replace(s[3:end-1], " " => "")
            parts = split(inner, ',')
            if length(parts) == 2
                c = try parse(Int, parts[1]) catch; -1 end
                t = try parse(Int, parts[2]) catch; -1 end
                if c > 0 && t > 0
                    z_idxs[(c, t)] = j
                    max_c = max(max_c, c)
                    max_t = max(max_t, t)
                end
            end
        end
    end
    # Discrete states-first order (by time then chain)
    disc_order = Int[]
    for t in 1:max_t
        for c in 1:max_c
            idx = get(z_idxs, (c, t), 0)
            if idx != 0
                push!(disc_order, idx)
            end
        end
    end
    return build_eval_order_from_discrete_order(model, disc_order)
end

# ==========================
# Heuristic Order Construction
# ==========================

## Helper previously used by heuristics removed to simplify experiments module
"""
    build_eval_order_from_discrete_order(model, disc_order)

Lift a discrete-variable elimination order to a full evaluation order by:
- Placing dependencies (direct parents) before each discrete var
- Placing observed nodes as soon as all their discrete parents are placed
- Topologically repairing remaining nodes
"""
function build_eval_order_from_discrete_order(model, disc_order::AbstractVector{<:Integer})
    gd = model.graph_evaluation_data
    order_nodes = gd.sorted_nodes
    n = length(order_nodes)
    pos = Dict(order_nodes[i] => i for i in 1:n)
    placed = fill(false, n)
    out = Int[]

    parents(vn) = collect(MetaGraphsNext.inneighbor_labels(model.g, vn))

    function place_with_dependencies(vn)
        i = pos[vn]
        if placed[i]; return; end
        for p in parents(vn)
            place_with_dependencies(p)
        end
        push!(out, i)
        placed[i] = true
    end

    # Precompute discrete parents of observed stochastic nodes
    st_parents = JModel._get_stochastic_parents_indices(model)
    obs_nodes = [i for i in 1:n if gd.is_stochastic_vals[i] && gd.is_observed_vals[i]]
    obs_disc_parents = Dict{Int,Vector{Int}}()
    for j in obs_nodes
        ps = [p for p in st_parents[j] if gd.is_discrete_finite_vals[p] && !gd.is_observed_vals[p]]
        obs_disc_parents[j] = ps
    end

    # Place discrete vars following disc_order, then any observed nodes whose discrete parents are all placed
    for idx in disc_order
        place_with_dependencies(order_nodes[idx])
        # Place ready observed nodes
        for j in obs_nodes
            if !placed[j]
                ps = obs_disc_parents[j]
                if all(placed[p] for p in ps)
                    place_with_dependencies(order_nodes[j])
                end
            end
        end
    end

    # Finally, place any remaining nodes
    for vn in order_nodes
        if !placed[pos[vn]]
            place_with_dependencies(vn)
        end
    end
    return out
end

## Heuristic helpers removed from experiments to keep focus on consistent orders

"""
    frontier_cost_proxy(model; K_hint=2)

Compute frontier statistics and a domain-aware proxy cost Σ_t K_hint^{width_t}.
Returns (max_width, mean_width, sum_width, proxy).
"""
function frontier_cost_proxy(model; K_hint::Real=2)
    gd = model.graph_evaluation_data
    order = gd.marginalization_order
    keys = gd.minimal_cache_keys
    widths = [length(get(keys, idx, Int[])) for idx in order]
    if isempty(widths)
        return 0, 0.0, 0, -Inf
    end
    logK = log(float(K_hint))
    # Stable log-sum-exp of w*logK
    log_terms = (w * logK for w in widths)
    proxy_log = LogExpFunctions.logsumexp(log_terms)
    return maximum(widths), mean(widths), sum(widths), proxy_log
end

"""
    topo_repair_order(model, desired_order)

Given a desired ordering of node indices (w.r.t. `model.graph_evaluation_data.sorted_nodes`),
return a topologically valid order that preserves the desired sequence as much as possible
while ensuring all direct parents are placed before each node.
"""
function topo_repair_order(model, desired_order::AbstractVector{<:Integer})
    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)
    desired = collect(desired_order)
    # Extend with any nodes not explicitly listed
    if length(desired) < n
        present = Set(desired)
        append!(desired, (i for i in 1:n if i ∉ present))
    end

    pos = Dict(gd.sorted_nodes[i] => i for i in 1:n)
    placed = fill(false, n)
    out = Int[]

    parents(vn) = collect(MetaGraphsNext.inneighbor_labels(model.g, vn))

    function place_with_dependencies(vn)
        i = pos[vn]
        if placed[i]
            return
        end
        for p in parents(vn)
            place_with_dependencies(p)
        end
        push!(out, i)
        placed[i] = true
    end

    for idx in desired
        vn = gd.sorted_nodes[idx]
        place_with_dependencies(vn)
    end
    # Safety: ensure all nodes placed
    for vn in gd.sorted_nodes
        place_with_dependencies(vn)
    end
    return out
end

"""
    make_model_with_order(model, order)

Return a new BUGSModel whose `graph_evaluation_data` carries the provided
topologically‑repaired marginalization order and the corresponding
`minimal_cache_keys` computed for that order.
"""
function make_model_with_order(model, order::AbstractVector{<:Integer})
    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)
    # Repair order to satisfy direct parent dependencies
    repaired = topo_repair_order(model, order)
    # Compute minimal cache keys for this evaluation order
    min_keys = JModel._precompute_minimal_cache_keys(model, repaired)
    # Build a new GraphEvaluationData reusing cached fields but with new order/keys
    gd2 = JModel.GraphEvaluationData{typeof(gd.node_function_vals),typeof(gd.loop_vars_vals)}(
        gd.sorted_nodes,
        gd.sorted_parameters,
        gd.is_stochastic_vals,
        gd.is_observed_vals,
        gd.node_function_vals,
        gd.loop_vars_vals,
        gd.node_types,
        gd.is_discrete_finite_vals,
        min_keys,
        repaired,
    )
    # Return a shallow‑copy model with updated GraphEvaluationData
    return JModel.BUGSModel(model; graph_evaluation_data=gd2)
end

"""
    build_states_first_order(model)

Construct an order that places all non (z,y) nodes first, then all z[i] by i,
then all y[i] by i. Intended for HMM‑style models and for demonstrating poor
ordering effects.
"""
function build_states_first_order(model)
    gd = model.graph_evaluation_data
    z_idxs = Dict{Int,Int}()
    y_idxs = Dict{Int,Int}()
    other = Int[]
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0
                z_idxs[i] = j
            else
                push!(other, j)
            end
        elseif startswith(s, "y[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0
                y_idxs[i] = j
            else
                push!(other, j)
            end
        else
            push!(other, j)
        end
    end
    order = copy(other)
    for i in sort!(collect(keys(z_idxs)))
        push!(order, z_idxs[i])
    end
    for i in sort!(collect(keys(y_idxs)))
        push!(order, y_idxs[i])
    end
    return order
end

"""
    build_fhmm_states_then_emissions_order(model)

Construct a consistent but poor order for FHMMs: place all non-(z,y) nodes first,
then all discrete states z[c,t] (by increasing t, then c), followed by all
emissions y[t]. This tends to maximize frontier width across time and
demonstrates intractability when ordering is poor.
"""
function build_fhmm_states_then_emissions_order(model)
    gd = model.graph_evaluation_data
    z_idxs = Dict{Tuple{Int,Int},Int}()
    y_idxs = Dict{Int,Int}()
    other = Int[]
    max_c, max_t = 0, 0
    for (j, vn) in enumerate(gd.sorted_nodes)
        s = string(vn)
        if startswith(s, "z[")
            inner = replace(s[3:end-1], " " => "")
            parts = split(inner, ',')
            if length(parts) == 2
                c = try parse(Int, parts[1]) catch; -1 end
                t = try parse(Int, parts[2]) catch; -1 end
                if c > 0 && t > 0
                    z_idxs[(c, t)] = j
                    max_c = max(max_c, c)
                    max_t = max(max_t, t)
                end
            end
        elseif startswith(s, "y[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0
                y_idxs[i] = j
            else
                push!(other, j)
            end
        else
            push!(other, j)
        end
    end
    order = copy(other)
    # All z's first (by time then chain)
    for t in 1:max_t
        for c in 1:max_c
            idx = get(z_idxs, (c, t), 0)
            if idx != 0
                push!(order, idx)
            end
        end
    end
    # Then all y's (by time)
    for t in sort(collect(keys(y_idxs)))
        push!(order, y_idxs[t])
    end
    return order
end

"""
    build_hmt_dfs_order(model; B_hint=2, rng=nothing, randomized=false)

Construct a discrete-first DFS order for HMTs (variables named `z[i]`, `y[i]`).
Discovers the tree structure directly from the model graph by following edges
between `z` nodes. If `randomized=true`, shuffles child order using `rng`.
Returns a full evaluation order via `build_eval_order_from_discrete_order`.
"""
function build_hmt_dfs_order(model; B_hint::Integer=2, rng=nothing, randomized::Bool=false)
    gd = model.graph_evaluation_data
    nodes = gd.sorted_nodes
    n = length(nodes)
    # Map VarName->sorted index and VarName->z index i
    pos = Dict(nodes[i] => i for i in 1:n)
    z_index = Dict{typeof(nodes[1]),Int}()
    for (j, vn) in enumerate(nodes)
        s = string(vn)
        if startswith(s, "z[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0
                z_index[vn] = i
            end
        end
    end
    # Build adjacency among z nodes via out-neighbors
    children = Dict{Int,Vector{Int}}()
    has_parent = Dict{Int,Bool}()
    for (vn, i) in z_index
        kids = Int[]
        for w in MetaGraphsNext.outneighbor_labels(model.g, vn)
            if haskey(z_index, w)
                j = z_index[w]
                push!(kids, j)
                has_parent[j] = true
            end
        end
        children[i] = kids
        has_parent[i] = get(has_parent, i, false)
    end
    # Roots: z nodes without z-parents
    roots = sort([i for (i, hp) in has_parent if !hp])
    order_z = Int[]  # sorted indices (positions) for z nodes
    # Helper: get VarName for a given z index i
    z_vn_by_i = Dict{Int,typeof(nodes[1])}()
    for (vn, i) in z_index
        z_vn_by_i[i] = vn
    end
    function dfs(i::Int)
        push!(order_z, pos[z_vn_by_i[i]])
        kids = get(children, i, Int[])
        if randomized && rng !== nothing
            Random.shuffle!(rng, kids)
        else
            sort!(kids)
        end
        for j in kids
            dfs(j)
        end
    end
    for r in roots
        dfs(r)
    end
    return build_eval_order_from_discrete_order(model, order_z)
end

"""
    build_hmt_bfs_order(model)

Construct a discrete-first BFS order for HMTs by level, discovered from the
graph. Returns a full evaluation order after lifting.
"""
function build_hmt_bfs_order(model)
    gd = model.graph_evaluation_data
    nodes = gd.sorted_nodes
    n = length(nodes)
    pos = Dict(nodes[i] => i for i in 1:n)
    z_index = Dict{typeof(nodes[1]),Int}()
    for (j, vn) in enumerate(nodes)
        s = string(vn)
        if startswith(s, "z[")
            i = try parse(Int, s[3:end-1]) catch; -1 end
            if i > 0
                z_index[vn] = i
            end
        end
    end
    children = Dict{Int,Vector{Int}}()
    has_parent = Dict{Int,Bool}()
    for (vn, i) in z_index
        kids = Int[]
        for w in MetaGraphsNext.outneighbor_labels(model.g, vn)
            if haskey(z_index, w)
                j = z_index[w]
                push!(kids, j)
                has_parent[j] = true
            end
        end
        children[i] = kids
        has_parent[i] = get(has_parent, i, false)
    end
    roots = sort([i for (i, hp) in has_parent if !hp])
    # BFS
    order_z = Int[]
    z_vn_by_i = Dict{Int,typeof(nodes[1])}()
    for (vn, i) in z_index
        z_vn_by_i[i] = vn
    end
    queue = copy(roots)
    while !isempty(queue)
        i = popfirst!(queue)
        push!(order_z, pos[z_vn_by_i[i]])
        kids = sort(get(children, i, Int[]))
        append!(queue, kids)
    end
    return build_eval_order_from_discrete_order(model, order_z)
end
