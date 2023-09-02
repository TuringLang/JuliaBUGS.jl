"""
    NodeInfo

Abstract type for storing node information in the BUGS model's dependency graph.
"""
abstract type NodeInfo end

"""
    AuxiliaryNodeInfo

Indicate the node is created by the compiler and not in the original BUGS model. These nodes
are only used to determine dependencies.

E.g., x[1:2] ~ dmnorm(...); y = x[1] + 1
In this case, x[1] is a auxiliary node, because it doesn't appear on the LHS of any expression.
But we still need to introduce it to determine the dependency between `y` and `x[1:2]`.

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
- `link_function_expr::Union{Expr,Symbol}`: The link function expression.
- `node_function_expr::Expr`: The node function expression.
- `node_args::Vector{VarName}`: A vector containing the names of the variables that are 
    arguments to the node function.

"""
struct ConcreteNodeInfo <: NodeInfo
    node_type::VariableTypes
    link_function_expr::Union{Expr,Symbol}
    node_function_expr::Expr
    node_args::Vector{VarName}
end

function ConcreteNodeInfo(var::Var, vars, link_functions, node_functions, node_args)
    return ConcreteNodeInfo(
        vars[var],
        link_functions[var],
        node_functions[var],
        map(v -> AbstractPPL.VarName{v.name}(AbstractPPL.IdentityLens()), node_args[var]),
    )
end

function is_logical(ni::ConcreteNodeInfo)
    return ni.node_type == Logical
end

"""
    eval([m::Module, ]ni::ConcreteNodeInfo, vi)

Evaluate a node under a specified module `m`. If no module is provided, the default module used is JuliaBUGS.
This function unpacks the node information from `ni` and evaluates the node function expression using the arguments
from the provided `vi` (variable information).
"""
function eval(ni::ConcreteNodeInfo, vi)
    return eval(JuliaBUGS, ni, vi)
end
function eval(m::Module, ni::ConcreteNodeInfo, vi)
    @unpack node_type, link_function_expr, node_function_expr, node_args = ni
    args = Dict(getsym(arg) => vi[arg] for arg in node_args)
    expr = node_function_expr.args[2]
    return _eval(m, expr, args)
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

function BUGSGraph(vars, link_functions, node_args, node_functions, dependencies)
    g = MetaGraph(
        SimpleDiGraph{Int64}();
        weight_function=nothing,
        label_type=VarName,
        vertex_data_type=NodeInfo,
    )
    for l in keys(vars) # l for LHS variable
        l_vn = to_varname(l)
        check_and_add_vertex!(
            g, l_vn, create_nodeinfo(l, vars, link_functions, node_functions, node_args)
        )
        # The use of AuxiliaryNodeInfo is also to save computation, becasue otherwise, 
        # every time we introduce a new node, we need to check `subsumes` or by all the existing nodes.
        scalarize_then_add_edge!(g, l; lhs_or_rhs=:lhs)
        for r in dependencies[l]
            r_vn = to_varname(r)
            check_and_add_vertex!(
                g, r_vn, create_nodeinfo(r, vars, link_functions, node_functions, node_args)
            )
            add_edge!(g, r_vn, l_vn)
            scalarize_then_add_edge!(g, r; lhs_or_rhs=:rhs)
        end
    end
    check_undeclared_variables(g, vars)
    remove_auxiliary_nodes!(g)
    return g
end

function create_nodeinfo(var::Var, vars, link_functions, node_functions, node_args)
    if var in keys(vars)
        return ConcreteNodeInfo(var, vars, link_functions, node_functions, node_args)
    else
        return AuxiliaryNodeInfo()
    end
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
