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

function markov_blanket(g::BUGSGraph, v; children_only=false)
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
