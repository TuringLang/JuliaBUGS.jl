struct NodeInfo{F}
    is_stochastic::Bool
    is_observed::Bool
    node_function_expr::Expr
    node_function::F
    node_args::Tuple{Vararg{Symbol}}
    loop_vars::NamedTuple
end

"""
    BUGSGraph


"""
const BUGSGraph = MetaGraph{
    Int,Graphs.SimpleDiGraph{Int},<:VarName,<:NodeInfo,Nothing,Nothing,<:Any,Float64
}

"""
    find_generated_vars(g::BUGSGraph)

Return all the logical variables without stochastic descendants. The values of these variables 
do not affect sampling process. These variables are called "generated quantities" traditionally.
"""
function find_generated_vars(g)
    graph_roots = VarName[] # root nodes of the graph
    for n in labels(g)
        if isempty(outneighbor_labels(g, n))
            push!(graph_roots, n)
        end
    end

    generated_vars = VarName[]
    for n in graph_roots
        if !g[n].is_stochastic
            push!(generated_vars, n) # graph roots that are Logical nodes are generated variables
            find_generated_vars_recursive_helper(g, n, generated_vars)
        end
    end
    return generated_vars
end

function find_generated_vars_recursive_helper(g, n, generated_vars)
    if n in generated_vars # already visited
        return nothing
    end
    for p in inneighbor_labels(g, n) # parents
        if p in generated_vars # already visited
            continue
        end
        if g[p].node_type == Stochastic
            continue
        end # p is a Logical Node
        if !any(x -> g[x].node_type == Stochastic, outneighbor_labels(g, p)) # if the node has stochastic children, it is not a root
            push!(generated_vars, p)
        end
        find_generated_vars_recursive_helper(g, p, generated_vars)
    end
end

"""
    markov_blanket(g::BUGSModel, v)

Find the Markov blanket of variable(s) `v` in graph `g`. `v` can be a single `VarName` or a vector/tuple of `VarName`.
The Markov Blanket of a variable is the set of variables that shield the variable from the rest of the
network. Effectively, the Markov blanket of a variable is the set of its parents, its children, and
its children's other parents (reference: https://en.wikipedia.org/wiki/Markov_blanket).

In the case of vector, the Markov Blanket is the union of the Markov Blankets of each variable 
minus the variables themselves (reference: Liu, X.-Q., & Liu, X.-S. (2018). Markov Blanket and Markov 
Boundary of Multiple Variables. Journal of Machine Learning Research, 19(43), 1–50.)

In the case of M-H acceptance ratio evaluation, only the logps of the children are needed, because the logp of the parents
and co-parents are not changed (their values are still needed to compute the distributions). 
"""
function markov_blanket(g::BUGSGraph, v::VarName; children_only=false)
    if !children_only
        parents = stochastic_inneighbors(g, v)
        children = stochastic_outneighbors(g, v)
        co_parents = VarName[]
        for p in children
            co_parents = vcat(co_parents, stochastic_inneighbors(g, p))
        end
        blanket = unique(vcat(parents, children, co_parents...))
        return [x for x in blanket if x != v]
    else
        return stochastic_outneighbors(g, v)
    end
end

function markov_blanket(g::BUGSGraph, v::Vector{<:VarName}; children_only=false)
    blanket = VarName[]
    for vn in v
        blanket = vcat(blanket, markov_blanket(g, vn; children_only=children_only))
    end
    return [x for x in unique(blanket) if x ∉ v]
end

"""
    stochastic_neighbors(g::BUGSGraph, c::VarName, f)
   
Internal function to find all the stochastic neighbors (parents or children), returns a vector of
`VarName` containing the stochastic neighbors and the logical variables along the paths.
"""
function stochastic_neighbors(
    g::BUGSGraph,
    v::VarName,
    f::Union{
        typeof(MetaGraphsNext.inneighbor_labels),typeof(MetaGraphsNext.outneighbor_labels)
    },
)
    stochastic_neighbors_vec = VarName[]
    logical_en_route = VarName[] # logical variables
    for u in f(g, v)
        if g[u].is_stochastic
            push!(stochastic_neighbors_vec, u)
        else
            push!(logical_en_route, u)
            ns = stochastic_neighbors(g, u, f)
            for n in ns
                push!(stochastic_neighbors_vec, n)
            end
        end
    end
    return [stochastic_neighbors_vec..., logical_en_route...]
end

"""
    stochastic_inneighbors(g::BUGSGraph, v::VarName)

Find all the stochastic inneighbors (parents) of `v`.
"""
function stochastic_inneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.inneighbor_labels)
end

"""
    stochastic_outneighbors(g::BUGSGraph, v::VarName)

Find all the stochastic outneighbors (children) of `v`.
"""
function stochastic_outneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.outneighbor_labels)
end

## Below are the new functions

is_stochastic(g::BUGSGraph, v::VarName) = g[v].is_stochastic
is_model_parameter(g::BUGSGraph, v::VarName) = g[v].is_stochastic && !g[v].is_observed
is_observation(g::BUGSGraph, v::VarName) = g[v].is_stochastic && g[v].is_observed
is_deterministic(g::BUGSGraph, v::VarName) = !g[v].is_stochastic

"""
    find_generated_quantities_variables(g::BUGSGraph)

Find all the generated quantities variables in the graph.

Generated quantities variables are variables that do not affect the sampling process. 
They are variables that do not have any descendant variables that are observed.
"""
function find_generated_quantities_variables(
    g::MetaGraph{Int,<:SimpleDiGraph,Label,VertexData}
) where {Label,VertexData}
    generated_quantities_variables = Set{Label}()
    can_reach_observations = Dict{Label,Bool}()

    for n in labels(g)
        if !is_observation(g, n)
            if !dfs_can_reach_observations(g, n, can_reach_observations)
                push!(generated_quantities_variables, n)
            end
        end
    end
    return generated_quantities_variables
end

function dfs_can_reach_observations(g, n, can_reach_observations)
    if haskey(can_reach_observations, n)
        return can_reach_observations[n]
    end

    if is_observation(g, n)
        can_reach_observations[n] = true
        return true
    end

    can_reach = false
    for child in MetaGraphsNext.outneighbor_labels(g, n)
        if dfs_can_reach_observations(g, child, can_reach_observations)
            can_reach = true
            break
        end
    end

    can_reach_observations[n] = can_reach
    return can_reach
end

"""
    markov_blanket(g::BUGSGraph, v)

Find the Markov blanket of variable(s) `v` in graph `g`. `v` can be a single `VarName` or a vector/tuple of `VarName`.

The Markov Blanket of a variable is the set of variables that shield the variable from the rest of the
network. Effectively, the Markov blanket of a variable is the set of its parents, its children, and 
its children's other parents (reference: https://en.wikipedia.org/wiki/Markov_blanket).

In the case of a vector of variables, the Markov Blanket is the union of the Markov Blankets of each variable 
minus the variables themselves[1].

This function returns a `Set` of `VarName`s, containing the Markov blanket of the variable(s) `v` in graph `g`, deterministic
variables that are on the path from `v` to their Markov blankets, and the variables `v` itself(themselves).

[1] Liu, X.-Q., & Liu, X.-S. (2018). Markov Blanket and Markov 
Boundary of Multiple Variables. Journal of Machine Learning Research, 19(43), 1–50.
"""
function _markov_blanket(g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::L) where {L,VD}
    if !is_stochastic(g, v)
        throw(ArgumentError("Variable $v is logical, so it has no Markov blanket."))
    end

    parents, deterministic_variables_en_route_parents = dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, v, MetaGraphsNext.inneighbor_labels
    )
    children, deterministic_variables_en_route_children = dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
        g, v, MetaGraphsNext.outneighbor_labels
    )

    co_parents, deterministic_variables_en_route_co_parents = Set{L}(), Set{L}()
    for child in children
        co_parents_child, deterministic_variables_en_route_co_parents_child = dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
            g, child, MetaGraphsNext.inneighbor_labels
        )
        union!(co_parents, co_parents_child)
        union!(
            deterministic_variables_en_route_co_parents,
            deterministic_variables_en_route_co_parents_child,
        )
    end

    blanket = union!(
        parents,
        children,
        co_parents,
        deterministic_variables_en_route_parents,
        deterministic_variables_en_route_children,
        deterministic_variables_en_route_co_parents,
    )
    push!(blanket, v)
    return blanket
end

function _markov_blanket(
    g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, vs::AbstractVector{<:L}
) where {L,VD}
    return reduce((acc, vn) -> union!(acc, _markov_blanket(g, vn)), vs; init=Set{L}())
end

function _markov_blanket(
    g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, vs::Tuple{Vararg{L}}
) where {L,VD}
    return reduce((acc, vn) -> union!(acc, _markov_blanket(g, vn)), vs; init=Set{L}())
end

function dfs_find_stochastic_boundary_and_deterministic_variables_en_route(
    g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::L, neighbor_func::F
) where {L,VD,F}
    stochastic_neighbors = Set{L}()
    deterministic_variables_en_route = Set{L}()
    stack = L[v]
    visited = Set{L}()

    while !isempty(stack)
        current = pop!(stack)
        current in visited && continue

        if is_deterministic(g, current)
            push!(deterministic_variables_en_route, current)
        end

        push!(visited, current)

        for neighbor in neighbor_func(g, current)
            if !(neighbor in visited)
                if is_stochastic(g, neighbor)
                    push!(stochastic_neighbors, neighbor)
                    # and stop (not pushing to stack)
                else
                    push!(stack, neighbor)
                end
            end
        end
    end

    return stochastic_neighbors, deterministic_variables_en_route
end
