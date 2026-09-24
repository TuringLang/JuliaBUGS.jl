# Cut models (Plummer 2015)
#
# `cut(x)` marks the boundary between an upstream module (parameters φ, data Z) and a
# downstream module (parameters θ, data Y). `cut_upstream_model` derives the model whose
# target is p(φ | Z); `cut_downstream_model` derives the model whose target is
# p(θ | φ, Y) with φ fixed. `NestedCut` (src/nested_cut.jl) alternates between them.

function _is_cut_call(ex)
    Meta.isexpr(ex, :call) || return false
    f = ex.args[1]
    return f === :cut || (Meta.isexpr(f, :.) && f.args[end] == QuoteNode(:cut))
end

function _is_cut_node(node_info::JuliaBUGS.NodeInfo)
    node_info.is_stochastic && return false
    body = node_info.node_function_expr.args[2]
    ret = body.args[end]
    return Meta.isexpr(ret, :return) && _is_cut_call(ret.args[1])
end

cut_nodes(g::BUGSGraph) = VarName[vn for vn in labels(g) if _is_cut_node(g[vn])]

struct CutPartition
    cut_nodes::Vector{VarName}
    module2::Set{VarName}          # all nodes (any type) in module 2
end

# Breadth-first traversal over `neighbor_fn` labels, never entering a cut-node vertex.
function _bfs_labels(g::BUGSGraph, seeds, neighbor_fns, cut_set::Set{<:VarName})
    seen = Set{VarName}()
    queue = VarName[]
    for vn in seeds
        vn ∉ seen && push!(queue, vn)
    end
    while !isempty(queue)
        vn = pop!(queue)
        (vn ∈ cut_set || vn in seen) && continue
        push!(seen, vn)
        for neighbor_fn in neighbor_fns
            for nb in neighbor_fn(g, vn)
                nb ∉ seen && push!(queue, nb)
            end
        end
    end
    return seen
end

function _cut_partition(g::BUGSGraph)
    cuts = cut_nodes(g)
    isempty(cuts) && throw(
        ArgumentError(
            "The model has no `cut` node; mark the module boundary with `x_cut = cut(x)`.",
        ),
    )
    cut_set = Set{VarName}(cuts)

    # Nodes strictly downstream of the cut nodes.
    descendant_seeds = Iterators.flatmap(c -> MetaGraphsNext.outneighbor_labels(g, c), cuts)
    descendants = _bfs_labels(
        g, descendant_seeds, (MetaGraphsNext.outneighbor_labels,), cut_set
    )

    # Module 2: union of the weakly connected components containing any descendant,
    # in the graph with the cut nodes deleted.
    module2 = _bfs_labels(
        g,
        descendants,
        (MetaGraphsNext.outneighbor_labels, MetaGraphsNext.inneighbor_labels),
        cut_set,
    )

    ancestor_seeds = Iterators.flatmap(c -> MetaGraphsNext.inneighbor_labels(g, c), cuts)
    ancestors = _bfs_labels(g, ancestor_seeds, (MetaGraphsNext.inneighbor_labels,), cut_set)

    offenders = sort!(collect(intersect(ancestors, module2)); by=string)
    isempty(offenders) || throw(
        ArgumentError(
            "`cut` does not separate the model: $(first(offenders)) is both upstream " *
            "of a cut and connected to the downstream module",
        ),
    )

    return CutPartition(cuts, module2)
end

"""
    cut_upstream_model(model::BUGSModel)

Model whose target is p(module-1 parameters | module-1 observations): every stochastic node
downstream of the cut (module 2) is dropped from the target and classified as a generated
quantity.
"""
function cut_upstream_model(model::BUGSModel)
    partition = _cut_partition(model.g)
    module2_observed = VarName[
        vn for vn in partition.module2 if JuliaBUGS.is_observation(model.g, vn)
    ]
    new_graph = _mark_as_unobserved(model.g, module2_observed)
    default_gq =
        GraphEvaluationData(
            new_graph; fixed_parameters=Set{VarName}(fixed_parameters(model))
        ).generated_quantities
    gq = union(
        Set{VarName}(default_gq), partition.module2, Set{VarName}(partition.cut_nodes)
    )
    return _create_modified_model(
        model,
        new_graph,
        model.evaluation_env;
        generated_quantities=gq,
        preserve_generated_quantities=false,
    )
end

"""
    cut_downstream_model(model::BUGSModel)

Model whose target is p(module-2 parameters | module-1 parameters, data): the module-1
parameters are `fix`ed at the values in `model.evaluation_env`.
"""
function cut_downstream_model(model::BUGSModel)
    upstream = cut_upstream_model(model)
    upstream_params = model_parameters(upstream)
    return isempty(upstream_params) ? model : fix(model, upstream_params)
end
