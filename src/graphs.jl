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

The `BUGSGraph` object represents the graph structure for a BUGS model.
"""
const BUGSGraph = MetaGraph{
    Int,Graphs.SimpleDiGraph{Int},<:VarName,<:NodeInfo,Nothing,Nothing,<:Any,Float64
}

is_model_parameter(g::BUGSGraph, v::VarName) = g[v].is_stochastic && !g[v].is_observed
is_observation(g::BUGSGraph, v::VarName) = g[v].is_stochastic && g[v].is_observed
is_deterministic(g::BUGSGraph, v::VarName) = !g[v].is_stochastic
is_stochastic(g::BUGSGraph, v::VarName) = g[v].is_stochastic

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
    markov_blanket(g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::L) where {L,VD}

Find the Markov blanket of variable(s) `v` in graph `g`. `v` can be a single `VarName` or a vector/tuple of `VarName`.

The Markov Blanket of a variable is the set of variables that shield the variable from the rest of the
network. Effectively, the Markov blanket of a variable is the set of its parents, its children, and 
its children's other parents (reference: https://en.wikipedia.org/wiki/Markov_blanket).

In the case of a vector of variables, the Markov Blanket is the union of the Markov Blankets of each variable 
minus the variables themselves[1].

[1] Liu, X.-Q., & Liu, X.-S. (2018). Markov Blanket and Markov 
Boundary of Multiple Variables. Journal of Machine Learning Research, 19(43), 1–50.
"""
function markov_blanket(g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::L) where {L,VD}
    if !is_stochastic(g, v)
        throw(ArgumentError("Variable $v is logical, so it has no Markov blanket."))
    end

    parents, logical_along_path_parents = stochastic_inneighbors(g, v)
    children, logical_along_path_children = stochastic_outneighbors(g, v)
    co_parents, logical_along_path_co_parents = Set{L}(), Set{L}()

    for child in children
        co_parents_child, logical_along_path_co_parents_child = stochastic_inneighbors(g, child)
        union!(co_parents, co_parents_child)
        union!(logical_along_path_co_parents, logical_along_path_co_parents_child)
    end

    blanket = union!(parents, children, co_parents, logical_along_path_parents, logical_along_path_children, logical_along_path_co_parents)
    delete!(blanket, v)
    return blanket
end

function markov_blanket(
    g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::Union{Vector{L},NTuple{N,<:L}}
) where {L,VD,N}
    blanket = reduce((acc, vn) -> union!(acc, markov_blanket(g, vn)), v; init=Set{L}())
    return setdiff(blanket, Set(v))
end

function dfs_find_stochastic_boundary_and_variables_along_the_path(
    g::MetaGraph{Int,<:SimpleDiGraph,L,VD}, v::L, f::F
) where {L,VD,F}
    if !is_stochastic(g, v)
        throw(ArgumentError("Variable $v is not stochastic, this function is for stochastic variables only."))
    end

    stochastic_neighbors = Set{L}()
    deterministic_variables_along_path = Set{L}()
    stack = [v]
    visited = Set{L}()

    while !isempty(stack)
        current = pop!(stack)

        if current in visited
            continue
        end
        
        if is_deterministic(g, current)
            push!(deterministic_variables_along_path, current)
        end

        push!(visited, current)
        neighbors = f(g, current)

        for u in neighbors
            if !(u in visited)
                if is_stochastic(g, u)
                    push!(stochastic_neighbors, u)
                else
                    push!(stack, u)
                end
            end
        end
    end

    return stochastic_neighbors, deterministic_variables_along_path
end

function stochastic_inneighbors(g, v)
    return dfs_find_stochastic_boundary_and_variables_along_the_path(g, v, MetaGraphsNext.inneighbor_labels)
end

function stochastic_outneighbors(g, v)
    return dfs_find_stochastic_boundary_and_variables_along_the_path(g, v, MetaGraphsNext.outneighbor_labels)
end
