struct VertexInfo
    is_stochastic::Bool
    is_observed::Bool
    node_function_expr::Expr
    node_args::Vector
    loop_vars::NamedTuple
end

abstract type GraphBuildingStage end

struct AddVertices <: GraphBuildingStage
    g::MetaGraph
    vertex_id_tracker::Dict
end

function AddVertices(eval_env::NamedTuple)
    g = MetaGraph(DiGraph(); label_type=VarName, vertex_data_type=VertexInfo)
    vertex_id_tracker = Dict{Symbol,Any}()
    for (k, v) in pairs(eval_env)
        if v isa AbstractArray
            vertex_id_tracker[k] = zeros(Int, size(v))
        else
            vertex_id_tracker[k] = 0
        end
    end
    return AddVertices(g, vertex_id_tracker)
end

struct AddEdges <: GraphBuildingStage
    g::MetaGraph
    vertex_id_tracker::Dict
end

function build_graph(model_def::Expr, eval_env::NamedTuple)
    stage = AddVertices(eval_env)
    build_graph(stage, model_def, eval_env, NamedTuple())
    stage = AddEdges(stage.g, stage.vertex_id_tracker)
    build_graph(stage, model_def, eval_env, NamedTuple())
    return stage.g
end

function build_graph(
    stage::GraphBuildingStage, expr::Expr, eval_env::NamedTuple, loop_vars::NamedTuple
)
    for statement in expr.args
        if Meta.isexpr(statement, :(=)) ||
            (Meta.isexpr(statement, :call) && statement.args[1] == :(~))
            build_graph_statement(stage, statement, eval_env, loop_vars)
        elseif Meta.isexpr(statement, :for)
            loop_var, lb, ub, body = decompose_for_expr(statement)
            lb, ub = Int(simple_arithmetic_eval(eval_env, lb)),
            Int(simple_arithmetic_eval(eval_env, ub))
            build_graph(stage, body, eval_env, merge(loop_vars, (loop_var => lb:ub,)))
        else
            error("Unknown statement type: $statement")
        end
    end
end

function build_graph_statement(
    stage::AddVertices, expr::Expr, eval_env::NamedTuple, loop_vars::NamedTuple
)
    lhs_expr, rhs_expr = Meta.isexpr(expr, :(=)) ? expr.args[1:2] : expr.args[2:3]
    node_function_expr, args = make_function_expr(
        rhs_expr, eval_env, Tuple(keys(loop_vars))
    )
    for loop_var_values in Iterators.product(values(loop_vars)...)
        loop_var_bindings = NamedTuple{Tuple(keys(loop_vars))}(loop_var_values)
        env = merge(eval_env, loop_var_bindings)
        lhs = simplify_lhs(env, lhs_expr)
        is_stochastic = false
        is_observed = false
        if Meta.isexpr(expr, :(=))
            lhs_value = if lhs isa Symbol
                value = env[lhs]
                if value isa Ref
                    value = value[]
                end
                value
            else
                var, indices... = lhs
                env[var][indices...]
            end
            if is_resolved(lhs_value)
                return nothing
            end
        else
            is_stochastic = true
            lhs_value = if lhs isa Symbol
                value = env[lhs]
                if value isa Ref
                    value = value[]
                end
                value
            else
                var, indices... = lhs
                env[var][indices...]
            end
            if is_observed
                is_observed = true
            end
        end

        vn = if lhs isa Symbol
            AbstractPPL.VarName{lhs}(AbstractPPL.IdentityLens())
        else
            v, indices... = lhs
            AbstractPPL.VarName{v}(AbstractPPL.IndexLens(indices))
        end
        add_vertex!(
            stage.g,
            vn,
            VertexInfo(
                is_stochastic, is_observed, node_function_expr, args, loop_var_bindings
            ),
        )
        if lhs isa Symbol
            stage.vertex_id_tracker[lhs] = code_for(stage.g, vn)
        else
            v, indices... = lhs
            if any(indices) do i
                i isa UnitRange
            end
                stage.vertex_id_tracker[v][indices...] .= code_for(stage.g, vn)
            else
                stage.vertex_id_tracker[v][indices...] = code_for(stage.g, vn)
            end
        end
    end
end

function make_function_expr(
    expr::Expr, env::NamedTuple{vars}, loop_vars::Tuple{Vararg{Symbol}}
) where {vars}
    var_with_numdims = extract_variable_names_and_numdims(expr)
    args = setdiff(keys(var_with_numdims), loop_vars)
    arg_exprs = []
    for v in args
        if v ∈ vars
            value = env[v]
            if value isa Int
                push!(arg_exprs, Expr(:(::), v, :Int))
            elseif value isa Float64
                push!(arg_exprs, Expr(:(::), v, :Float64))
            elseif value isa Ref
                push!(arg_exprs, Expr(:(::), v, :(Union{Int,Float64})))
            elseif value isa AbstractArray
                if eltype(value) === Int
                    push!(arg_exprs, Expr(:(::), v, :{Array{Int}}))
                elseif eltype(value) === Float64
                    push!(arg_exprs, Expr(:(::), v, :{Array{Float64,1}}))
                else
                    push!(arg_exprs, Expr(:(::), v, :{Array{Union{Int,Float64,Missing}}}))
                end
            else
                error("Unexpected argument type: $(typeof(value))")
            end
        else # loop vars
            push!(arg_exprs, Expr(:(::), v, :Int))
        end
    end

    return (MacroTools.@q function ($(arg_exprs...))
        return $(expr)
    end), args
end

function build_graph_statement(
    stage::AddEdges, expr::Expr, eval_env::NamedTuple, loop_vars::NamedTuple
)
    lhs_expr, rhs_expr = Meta.isexpr(expr, :(=)) ? expr.args[1:2] : expr.args[2:3]
    for loop_var_values in Iterators.product(values(loop_vars)...)
        loop_var_bindings = NamedTuple{Tuple(keys(loop_vars))}(loop_var_values)
        env = merge(eval_env, loop_var_bindings)
        lhs = simplify_lhs(env, lhs_expr)
        if Meta.isexpr(expr, :(=))
            lhs_value = if lhs isa Symbol
                value = env[lhs]
                if value isa Ref
                    value = value[]
                end
                value
            else
                var, indices... = lhs
                env[var][indices...]
            end
            if is_resolved(lhs_value)
                return nothing
            end
        end
        value, dependencies, _ = evaluate_and_track_dependencies(rhs_expr, env)

        lhs_vn = if lhs isa Symbol
            AbstractPPL.VarName{lhs}(AbstractPPL.IdentityLens())
        else
            v, indices... = lhs
            AbstractPPL.VarName{v}(AbstractPPL.IndexLens(indices))
        end

        for var in dependencies
            vertex_code = if var isa Symbol
                stage.vertex_id_tracker[var]
            else
                v, indices... = var
                stage.vertex_id_tracker[v][indices...]
            end

            vertex_code = filter(
                x -> x != 0, vertex_code isa Vector ? vertex_code : [vertex_code]
            )
            vertex_labels = map(x -> label_for(stage.g, x), vertex_code)
            for r in vertex_labels
                if r != lhs_vn
                    add_edge!(stage.g, r, lhs_vn)
                end
            end
        end
    end
end

"""
    find_generated_vars(g::MetaGraph)

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

In the case of M-H acceptance ratio evaluation, only the logps of the children are needed, because the logp of the parents
and co-parents are not changed (their values are still needed to compute the distributions). 
"""
function markov_blanket(g::MetaGraph, v::VarName; children_only=false)
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

function markov_blanket(g::MetaGraph, v; children_only=false)
    blanket = VarName[]
    for vn in v
        blanket = vcat(blanket, markov_blanket(g, vn; children_only=children_only))
    end
    return [x for x in unique(blanket) if x ∉ v]
end

"""
    stochastic_neighbors(g::MetaGraph, c::VarName, f)
   
Internal function to find all the stochastic neighbors (parents or children), returns a vector of
`VarName` containing the stochastic neighbors and the logical variables along the paths.
"""
function stochastic_neighbors(
    g::MetaGraph,
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
    stochastic_inneighbors(g::MetaGraph, v::VarName)

Find all the stochastic inneighbors (parents) of `v`.
"""
function stochastic_inneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.inneighbor_labels)
end

"""
    stochastic_outneighbors(g::MetaGraph, v::VarName)

Find all the stochastic outneighbors (children) of `v`.
"""
function stochastic_outneighbors(g, v)
    return stochastic_neighbors(g, v, MetaGraphsNext.outneighbor_labels)
end
