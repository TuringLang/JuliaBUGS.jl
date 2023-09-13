abstract type NodeInfo end

"""
    AuxiliaryNodeInfo

Indicate the node is created by the compiler and not in the original BUGS model. These nodes
are only used to determine dependencies.

E.g., x[1:2] ~ dmnorm(...); y = x[1] + 1
In this case, x[1] is an auxiliary node because it doesn't appear on the LHS of any expression.
But we must still introduce it to determine the dependency between `y` and `x[1:2]`.

In the current implementation, `AuxiliaryNodeInfo` is only used when constructing the graph,
and will all be removed right before returning the graph. 
"""
struct AuxiliaryNodeInfo <: NodeInfo end

"""
    ConcreteNodeInfo

Defines the information stored in each node of the BUGS graph, encapsulating the essential characteristics 
and functions associated with a node within the BUGS model's dependency graph.

# Fields

- `node_type::VariableTypes`: Specifies whether the node is a stochastic or logical variable.
- `node_function_expr::Expr`: The node function expression.
- `node_args::Vector{VarName}`: A vector containing the names of the variables that are 
    arguments to the node function.

"""
struct ConcreteNodeInfo <: NodeInfo
    node_type::VariableTypes
    node_function_expr::Expr
    node_args::Vector{VarName}
end

function ConcreteNodeInfo(var::Var, vars, node_functions, node_args)
    return ConcreteNodeInfo(
        vars[var],
        node_functions[var],
        map(v -> AbstractPPL.VarName{v.name}(AbstractPPL.IdentityLens()), node_args[var]),
    )
end

function NodeInfo(var::Var, vars, node_functions, node_args)
    if var in keys(vars)
        return ConcreteNodeInfo(var, vars, node_functions, node_args)
    else
        return AuxiliaryNodeInfo()
    end
end

"""
    BUGSGraph

The `BUGSGraph` object represents the graph structure for a BUGS model. It is a type alias for
[`MetaGraphsNext.MetaGraph`](https://juliagraphs.org/MetaGraphsNext.jl/dev/api/#MetaGraphsNext.MetaGraph)
with node type specified to [`ConcreteNodeInfo`](@ref).
"""
const BUGSGraph = MetaGraph{
    Int64,SimpleDiGraph{Int64},VarName,NodeInfo,Nothing,Nothing,Nothing,Float64
}

function BUGSGraph(vars, node_args, node_functions, dependencies)
    g = MetaGraph(
        SimpleDiGraph{Int64}();
        weight_function=nothing,
        label_type=VarName,
        vertex_data_type=NodeInfo,
    )
    for l in keys(vars) # l for LHS variable
        l_vn = to_varname(l)
        check_and_add_vertex!(g, l_vn, NodeInfo(l, vars, node_functions, node_args))
        # The use of AuxiliaryNodeInfo is also to save computation, becasue otherwise, 
        # every time we introduce a new node, we need to check `subsumes` or by all the existing nodes.
        scalarize_then_add_edge!(g, l; lhs_or_rhs=:lhs)
        for r in dependencies[l]
            r_vn = to_varname(r)
            check_and_add_vertex!(g, r_vn, NodeInfo(r, vars, node_functions, node_args))
            add_edge!(g, r_vn, l_vn)
            scalarize_then_add_edge!(g, r; lhs_or_rhs=:rhs)
        end
    end
    check_undeclared_variables(g, vars)
    remove_auxiliary_nodes!(g)
    return g
end

"""
    check_undeclared_variables

Check for undeclared variables within the model definition
"""
function check_undeclared_variables(g::BUGSGraph, vars)
    undeclared_vars = VarName[]
    for v in labels(g)
        if g[v] isa AuxiliaryNodeInfo
            children = outneighbor_labels(g, v)
            parents = inneighbor_labels(g, v)
            if isempty(parents) || isempty(children)
                if !any(
                    AbstractPPL.subsumes(u, v) || AbstractPPL.subsumes(v, u) for # corner case x[1:1] and x[1], e.g. Leuk
                    u in to_varname.(keys(vars))
                )
                    push!(undeclared_vars, v)
                end
            end
        end
    end
    if !isempty(undeclared_vars)
        error("Undeclared variables: $(string.(Symbol.(undeclared_vars)))")
    end
end

function remove_auxiliary_nodes!(g::BUGSGraph)
    for v in collect(labels(g))
        if g[v] isa AuxiliaryNodeInfo
            # fix dependencies
            children = outneighbor_labels(g, v)
            parents = inneighbor_labels(g, v)
            for c in children
                for p in parents
                    @assert !any(x -> x isa AuxiliaryNodeInfo, (g[c], g[p])) "Auxiliary nodes should not have neighbors that are also auxiliary nodes, but at least one of $(g[c]) and $(g[p]) are."
                    add_edge!(g, p, c)
                end
            end
            delete!(g, v)
        end
    end
end

function check_and_add_vertex!(g::BUGSGraph, v::VarName, data::NodeInfo)
    if haskey(g, v)
        data isa AuxiliaryNodeInfo && return nothing
        if g[v] isa AuxiliaryNodeInfo
            set_data!(g, v, data)
        end
    else
        add_vertex!(g, v, data)
    end
end

function scalarize_then_add_edge!(g::BUGSGraph, v::Var; lhs_or_rhs=:lhs)
    scalarized_v = vcat(scalarize(v)...)
    length(scalarized_v) == 1 && return nothing
    v = to_varname(v)
    for v_elem in map(to_varname, scalarized_v)
        add_vertex!(g, v_elem, AuxiliaryNodeInfo()) # may fail, in that case, the existing node may be concrete, so we don't need to add it
        if lhs_or_rhs == :lhs # if an edge exist between v and scalaized elements, don't add again
            !Graphs.has_edge(g, code_for(g, v_elem), code_for(g, v)) &&
                add_edge!(g, v, v_elem)
        elseif lhs_or_rhs == :rhs
            !Graphs.has_edge(g, code_for(g, v), code_for(g, v_elem)) &&
                add_edge!(g, v_elem, v)
        else
            error("Unknown argument $lhs_or_rhs")
        end
    end
end

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
        if g[n].node_type == Logical
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
"""
function markov_blanket(g::BUGSGraph, v::VarName)
    parents = stochastic_inneighbors(g, v)
    children = stochastic_outneighbors(g, v)
    co_parents = VarName[]
    for p in children
        co_parents = vcat(co_parents, stochastic_inneighbors(g, p))
    end
    blanket = unique(vcat(parents, children, co_parents...))
    return [x for x in blanket if x != v]
end

function markov_blanket(g::BUGSGraph, v)
    blanket = VarName[]
    for vn in v
        blanket = vcat(blanket, markov_blanket(g, vn))
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
        if g[u] isa ConcreteNodeInfo
            if g[u].node_type == Stochastic
                push!(stochastic_neighbors_vec, u)
            else
                push!(logical_en_route, u)
                ns = stochastic_neighbors(g, u, f)
                for n in ns
                    push!(stochastic_neighbors_vec, n)
                end
            end
        else
            # auxiliary nodes are not counted as logical nodes
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
