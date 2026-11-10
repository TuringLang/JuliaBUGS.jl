# Statement-grouped graph evaluation
#
# The reference graph evaluator visits `sorted_nodes` one node at a time. Its node
# functions, loop variables, and variable names are stored in `Any`-typed vectors, so every
# node pays for dynamic dispatch, a `Dict{VarName}` length lookup, and an `evaluation_env`
# rebuild that the compiler cannot see through.
#
# Nodes unrolled from the same BUGS statement share one node function, one loop-variable
# type, and one `VarName` type. A `GraphEvaluationPlan` reorders the nodes that log-density
# evaluation visits into a topological order that keeps such nodes together, and stores each
# group as a concretely typed `NodeRun`. Dispatch then happens once per run, not once per
# node, and parameter offsets are precomputed for both parameter spaces.
#
# The plan changes only the order in which nodes are visited, never which nodes are visited
# or what they compute:
# - the parameter layout (offsets into the flat vector) follows `sorted_nodes`, exactly as in
#   the reference evaluator;
# - the visit order is a topological order of the graph restricted to the visited nodes, so
#   every node reads only values written earlier in the same evaluation;
# - values are written with the same `BangBang.setindex!!` calls, so an environment field
#   widens exactly when the reference evaluator would widen it.
# Only the summation order of the log-density terms differs.

struct DeterministicNodeRun end
struct ParameterNodeRun end
struct ObservationNodeRun end

"""
    NodeRun{K,F,LV,VN}

Nodes of one kind `K` that share the node function `node_function`, evaluated in order.
`transformed_offsets`/`transformed_lengths` and `untransformed_offsets`/`untransformed_lengths`
locate each parameter in the flat parameter vector; they are empty for other kinds.
"""
struct NodeRun{K,F,LV,VN} <: AbstractNodeRun
    node_function::F
    loop_vars::Vector{LV}
    vns::Vector{VN}
    transformed_offsets::Vector{Int}
    transformed_lengths::Vector{Int}
    untransformed_offsets::Vector{Int}
    untransformed_lengths::Vector{Int}
end

_node_run_kind(::NodeRun{K}) where {K} = K

function _plan_node_kind(gd::GraphEvaluationData, i::Int)
    if !gd.is_stochastic_vals[i]
        return DeterministicNodeRun
    elseif gd.is_observed_vals[i]
        return ObservationNodeRun
    else
        return ParameterNodeRun
    end
end

# The nodes `evaluate_with_values!!` visits: deterministic nodes and observations inside the
# target closure, and the model parameters that occupy the flat parameter vector.
function _plan_visits_node(gd::GraphEvaluationData, i::Int)
    vt = gd.variable_types[i]
    (vt == GeneratedQuantity || vt == FixedParameter) && return false
    !gd.is_stochastic_vals[i] && return true
    gd.is_observed_vals[i] && return true
    return gd.is_model_parameter_vals[i]
end

"""
    _grouped_topological_runs(g, gd)

Partition the nodes visited by log-density evaluation into runs, returned in a valid
evaluation order. Each run holds nodes with the same node function, node kind, loop-variable
type, and `VarName` type, listed in an order consistent with the graph.

This is Kahn's algorithm over the graph restricted to visited nodes, with the ready nodes
bucketed by group. A bucket is drained (including members that become ready while draining)
before another is started. Buckets are chosen by priority:

1. a bucket holding every remaining member of its group, so the group finishes in one run;
2. a bucket whose members have visited children, since those unblock later work;
3. any other bucket. Its members have no visited children, so deferring it never blocks
   anything, and it eventually becomes a complete bucket of priority 1.

Ties go to the bucket with the earliest position in `sorted_nodes`.
"""
function _grouped_topological_runs(g::BUGSGraph, gd::GraphEvaluationData)
    sorted_nodes = gd.sorted_nodes
    n = length(sorted_nodes)
    position = Dict{eltype(sorted_nodes),Int}()
    sizehint!(position, n)
    for i in 1:n
        position[sorted_nodes[i]] = i
    end
    visited = [_plan_visits_node(gd, i) for i in 1:n]

    children = [Int[] for _ in 1:n]
    indegree = zeros(Int, n)
    for i in 1:n
        visited[i] || continue
        for parent in MetaGraphsNext.inneighbor_labels(g, sorted_nodes[i])
            j = get(position, parent, 0)
            (j == 0 || !visited[j]) && continue
            push!(children[j], i)
            indegree[i] += 1
        end
    end

    # Group ids. Nodes from different statements have distinct node function objects, and
    # `Dict` compares them with `===`, so two statements never share a group.
    group_of = zeros(Int, n)
    group_ids = Dict{Any,Int}()
    for i in 1:n
        visited[i] || continue
        key = (
            gd.node_function_vals[i],
            _plan_node_kind(gd, i),
            typeof(gd.loop_vars_vals[i]),
            typeof(sorted_nodes[i]),
        )
        group_of[i] = get!(group_ids, key, length(group_ids) + 1)
    end
    n_groups = length(group_ids)
    remaining = zeros(Int, n_groups)
    has_children = falses(n_groups)
    for i in 1:n
        visited[i] || continue
        remaining[group_of[i]] += 1
        isempty(children[i]) || (has_children[group_of[i]] = true)
    end

    ready = [Int[] for _ in 1:n_groups]
    ready_min = fill(typemax(Int), n_groups)
    function mark_ready!(i)
        k = group_of[i]
        push!(ready[k], i)
        ready_min[k] = min(ready_min[k], i)
        return nothing
    end
    for i in 1:n
        visited[i] && indegree[i] == 0 && mark_ready!(i)
    end

    runs = Vector{Vector{Int}}()
    n_emitted = 0
    while true
        best = 0
        best_score = (typemax(Int), typemax(Int))
        for k in 1:n_groups
            isempty(ready[k]) && continue
            priority = if length(ready[k]) == remaining[k]
                1
            elseif has_children[k]
                2
            else
                3
            end
            score = (priority, ready_min[k])
            if score < best_score
                best, best_score = k, score
            end
        end
        best == 0 && break

        run = Int[]
        while !isempty(ready[best])
            batch = sort!(ready[best])
            ready[best] = Int[]
            ready_min[best] = typemax(Int)
            for i in batch
                push!(run, i)
                remaining[best] -= 1
                for c in children[i]
                    indegree[c] -= 1
                    indegree[c] == 0 && mark_ready!(c)
                end
            end
        end
        push!(runs, run)
        n_emitted += length(run)
    end
    n_emitted == count(visited) || error(
        "Internal error: the model graph restricted to evaluated nodes is not acyclic."
    )
    return runs
end

"""
    _build_evaluation_plan(g, graph_evaluation_data, evaluation_env, mutable_symbols,
                           transformed_var_lengths, untransformed_var_lengths)

Build the statement-grouped evaluation plan used by [`evaluate_with_values!!`](@ref).
Returns `nothing` when a plan cannot be built, for example when a model parameter has no
recorded length; evaluation then uses the node-by-node graph evaluator.
"""
function _build_evaluation_plan(
    g::BUGSGraph,
    gd::GraphEvaluationData,
    evaluation_env::NamedTuple,
    mutable_symbols::Set{Symbol},
    transformed_var_lengths::Dict{<:VarName,Int},
    untransformed_var_lengths::Dict{<:VarName,Int},
)
    n = length(gd.sorted_nodes)
    transformed_offsets = zeros(Int, n)
    transformed_lengths = zeros(Int, n)
    untransformed_offsets = zeros(Int, n)
    untransformed_lengths = zeros(Int, n)
    t_offset, u_offset = 1, 1
    for (i, vn) in enumerate(gd.sorted_nodes)
        _plan_visits_node(gd, i) && _plan_node_kind(gd, i) === ParameterNodeRun || continue
        (haskey(transformed_var_lengths, vn) && haskey(untransformed_var_lengths, vn)) ||
            return nothing
        transformed_offsets[i] = t_offset
        transformed_lengths[i] = transformed_var_lengths[vn]
        untransformed_offsets[i] = u_offset
        untransformed_lengths[i] = untransformed_var_lengths[vn]
        t_offset += transformed_lengths[i]
        u_offset += untransformed_lengths[i]
    end

    runs = AbstractNodeRun[]
    for idxs in _grouped_topological_runs(g, gd)
        i1 = first(idxs)
        K = _plan_node_kind(gd, i1)
        # The source function, so that it can inline into the run's loop.
        f = JuliaBUGS._opaque_source(gd.node_function_vals[i1])
        # Grouping guarantees concrete element types; `map(identity, ...)` narrows them.
        loop_vars = map(identity, Any[gd.loop_vars_vals[i] for i in idxs])
        vns = map(identity, Any[gd.sorted_nodes[i] for i in idxs])
        is_param = K === ParameterNodeRun
        run = NodeRun{K,typeof(f),eltype(loop_vars),eltype(vns)}(
            f,
            loop_vars,
            vns,
            is_param ? transformed_offsets[idxs] : Int[],
            is_param ? transformed_lengths[idxs] : Int[],
            is_param ? untransformed_offsets[idxs] : Int[],
            is_param ? untransformed_lengths[idxs] : Int[],
        )
        push!(runs, run)
    end
    # Runs hold the source functions behind world-age-safe wrappers, see `_call_in_plan_world`.
    invoke_latest = any(f -> f isa JuliaBUGS._OpaqueClosureFunction, gd.node_function_vals)

    names = keys(evaluation_env)
    mutable_mask = NamedTuple{names}(map(k -> Val(k in mutable_symbols), names))
    return GraphEvaluationPlan(
        runs,
        invoke_latest,
        Base.get_world_counter(),
        mutable_mask,
        gd,
        transformed_var_lengths,
        untransformed_var_lengths,
        mutable_symbols,
    )
end

"""
    _evaluation_plan_is_current(plan, model)

Whether `plan` was built for the graph evaluation data, parameter lengths, and mutable
symbols that `model` holds now. Fields replaced with `BangBang.setproperty!!` keep the old
plan, so evaluation checks this before it uses a plan.
"""
function _evaluation_plan_is_current(plan::GraphEvaluationPlan, model)
    return plan.graph_evaluation_data === model.graph_evaluation_data &&
           plan.transformed_var_lengths === model.transformed_var_lengths &&
           plan.untransformed_var_lengths === model.untransformed_var_lengths &&
           plan.mutable_symbols === model.mutable_symbols
end
_evaluation_plan_is_current(::Nothing, model) = false

#######################
# Environment preparation
#######################

# Copy the fields that evaluation may write, as `smart_copy_evaluation_env` does. Floating
# point fields are created with the element type that writing a parameter of type `T` would
# give them anyway (for example a `ForwardDiff.Dual`), so they do not widen mid-evaluation.
struct _MutableFieldCopier{T} end

(::_MutableFieldCopier)(value, ::Val{false}) = value
(::_MutableFieldCopier{T})(value, ::Val{true}) where {T} = _copy_for_writing(value, T)

_copy_for_writing(value::AbstractFloat, ::Type{T}) where {T} = _widen_float(value, T)
function _copy_for_writing(value::AbstractArray{S}, ::Type{T}) where {S<:AbstractFloat,T}
    U = promote_type(S, T)
    isconcretetype(U) || return copy(value)
    return copyto!(similar(value, U), value)
end
function _copy_for_writing(value::AbstractArray{S}, ::Type) where {S}
    return isbitstype(S) || Base.isbitsunion(S) ? copy(value) : deepcopy(value)
end
_copy_for_writing(value, ::Type) = isbits(value) ? value : deepcopy(value)

function _widen_float(value::S, ::Type{T}) where {S<:AbstractFloat,T}
    U = promote_type(S, T)
    return isconcretetype(U) ? convert(U, value) : value
end

function _prepare_plan_env(
    env::NamedTuple, mask::NamedTuple, ::Type{T}, mutable_symbols
) where {T}
    # The environment was replaced by one with different fields since the plan was built.
    keys(env) === keys(mask) || return smart_copy_evaluation_env(env, mutable_symbols)
    return map(_MutableFieldCopier{T}(), env, mask)
end

#######################
# Execution
#######################

# Each method processes `run.vns[k:end]` and returns the updated environment and the
# accumulated log-prior and log-likelihood. When a write widens a field (for example an
# integer array receiving a floating-point value), the environment's type changes; the loop
# then continues in a fresh call specialized on the new type. This only keeps the loop type
# stable: the result would be the same without it.

function _execute_run(
    run::NodeRun{DeterministicNodeRun}, env::E, x, transformed, logprior, loglik, k=1
) where {E}
    f = run.node_function
    loop_vars = run.loop_vars
    vns = run.vns
    while k <= length(vns)
        value = f(env, @inbounds(loop_vars[k]))
        new_env = BangBang.setindex!!(env, value, @inbounds(vns[k]))
        k += 1
        if !(new_env isa E)
            return _execute_run(run, new_env, x, transformed, logprior, loglik, k)
        end
        env = new_env
    end
    return env, logprior, loglik
end

function _execute_run(
    run::NodeRun{ObservationNodeRun}, env, x, transformed, logprior, loglik
)
    f = run.node_function
    loop_vars = run.loop_vars
    vns = run.vns
    for k in eachindex(vns)
        dist = f(env, @inbounds(loop_vars[k]))
        loglik += logpdf(dist, AbstractPPL.getvalue(env, @inbounds(vns[k])))
    end
    return env, logprior, loglik
end

function _execute_run(
    run::NodeRun{ParameterNodeRun}, env::E, x, transformed, logprior, loglik, k=1
) where {E}
    f = run.node_function
    loop_vars = run.loop_vars
    vns = run.vns
    offsets = transformed ? run.transformed_offsets : run.untransformed_offsets
    lengths = transformed ? run.transformed_lengths : run.untransformed_lengths
    while k <= length(vns)
        dist = f(env, @inbounds(loop_vars[k]))
        start = @inbounds offsets[k]
        slice = view(x, start:(start + @inbounds(lengths[k]) - 1))
        if transformed
            b_inv = Bijectors.inverse(Bijectors.bijector(dist))
            value, logjac = Bijectors.with_logabsdet_jacobian(
                b_inv, reconstruct(b_inv, dist, slice)
            )
        else
            value = reconstruct(dist, slice)
            logjac = 0.0
        end
        logprior += logpdf(dist, value) + logjac
        new_env = BangBang.setindex!!(env, value, @inbounds(vns[k]))
        k += 1
        if !(new_env isa E)
            return _execute_run(run, new_env, x, transformed, logprior, loglik, k)
        end
        env = new_env
    end
    return env, logprior, loglik
end

_initial_logp(::Type{T}) where {T<:Real} = zero(promote_type(Float64, float(T)))
_initial_logp(::Type) = 0.0

function _execute_plan(runs::Vector{AbstractNodeRun}, env, x, transformed)
    T = eltype(x)
    logprior = _initial_logp(T)
    loglik = _initial_logp(T)
    for run in runs
        env, logprior, loglik = _execute_run(run, env, x, transformed, logprior, loglik)
    end
    return env, logprior, loglik
end

# Node functions are created by `eval`, so they can be newer than the world the caller runs
# in. `_OpaqueClosureFunction` makes each call world-age safe, but its non-inlined call
# dominates small nodes. Runs therefore call the source functions, and the plan is executed in
# a world that has them: the caller's, when it is recent enough, and otherwise the latest,
# entered once per evaluation. Mooncake and Enzyme differentiate a model built from source
# functions (see `_prepare_opaque_gradient`), whose plan never needs `invokelatest`.
function _call_in_plan_world(f, plan::GraphEvaluationPlan, args...)
    if plan.invoke_latest && ccall(:jl_get_tls_world_age, UInt, ()) < plan.world
        return Base.invokelatest(f, args...)
    end
    return f(args...)
end

function _execute_plan_with_temperature(runs, env, x, transformed, temperature)
    env, logprior, loglikelihood = _execute_plan(runs, env, x, transformed)
    return env,
    (
        logprior=logprior,
        loglikelihood=loglikelihood,
        tempered_logjoint=logprior + temperature * loglikelihood,
    )
end

function _evaluate_plan_with_values!!(
    plan::GraphEvaluationPlan, model, x::AbstractVector, temperature, transformed
)
    env = _prepare_plan_env(
        model.evaluation_env, plan.mutable_mask, eltype(x), model.mutable_symbols
    )
    return _call_in_plan_world(
        _execute_plan_with_temperature, plan, plan.runs, env, x, transformed, temperature
    )
end

function _execute_plan_logjoint(runs, env, x, transformed)
    _, logprior, loglikelihood = _execute_plan(runs, env, x, transformed)
    # `tempered_logjoint` at temperature one, as in `evaluate_with_values!!`.
    return logprior + 1.0 * loglikelihood
end

# The log joint alone, for `LogDensityProblems.logdensity` and its gradients.
function _plan_logjoint(plan::GraphEvaluationPlan, model, x::AbstractVector)
    env = _prepare_plan_env(
        model.evaluation_env, plan.mutable_mask, eltype(x), model.mutable_symbols
    )
    return _call_in_plan_world(
        _execute_plan_logjoint, plan, plan.runs, env, x, model.transformed
    )
end
