# Exact marginalization of finite discrete latents by variable elimination.
# The design is described in docs/src/developers/variable_elimination.md.
#
# With the continuous parameters fixed, each scored stochastic node adds a term to the log
# joint that depends on the latents only through the latents it reads, directly or through
# deterministic nodes: its scope. The marginal is a sum over latent configurations of a
# product of small tables, one per scored node with a non-empty scope, and is computed by
# summing the latents out one at a time.

"""
    MarginalizationFactor

The term one scored stochastic node adds to the log joint, as a table over its scope.

- `node`: index of the node in `sorted_nodes`.
- `scope`: the latents (indices into `VariableEliminationPlan.latents`) the term depends on,
  in increasing order. The table has one dimension per scope latent, in this order.
- `recompute`: the deterministic nodes and parameters whose values depend on the scope,
  which must be recomputed for every configuration, in topological order.
- `is_prior`: whether the term belongs to the log prior (a latent's or a continuous
  parameter's own distribution) rather than the log likelihood (an observation).
"""
struct MarginalizationFactor
    node::Int
    scope::Vector{Int}
    recompute::Vector{Int}
    is_prior::Bool
end

"""
    EliminationStep

Sum latent `latent` out of the tables in slots `inputs`, which together depend on the
latents `scope` (in increasing order), and store the result in slot `output`.
`input_shapes[k]` reshapes input `k` to `length(scope)` dimensions, with size 1 along the
latents it does not depend on, so the inputs can be added by broadcasting.
"""
struct EliminationStep
    latent::Int
    inputs::Vector{Int}
    input_shapes::Vector{Vector{Int}}
    scope::Vector{Int}
    output::Int
end

"""
    VariableEliminationPlan

Everything about marginalizing a model by variable elimination that does not depend on
the parameter values, fixed when the marginalization cache is built.

- `latents`: the `sorted_nodes` indices of the finite discrete latents.
- `domains`: the values each latent takes.
- `passthrough`: for each node, whether it is a continuous parameter whose value depends on
  latents, because its bijector depends on its parents (`a ~ dunif(lo[x], hi[x])`).
- `offsets`, `lengths`: for each continuous parameter, its slice of the parameter vector;
  zero for other nodes.
- `factors`: the factors, whose tables occupy the first `length(factors)` slots.
- `base_nodes`: scored nodes with an empty scope, scored once.
- `joint`, `prior`: elimination steps for all factors and for the prior factors only.
- `joint_leftovers`, `prior_leftovers`: the slots with an empty scope left at the end.
"""
struct VariableEliminationPlan
    latents::Vector{Int}
    domains::Vector{Vector{Int}}
    passthrough::Vector{Bool}
    offsets::Vector{Int}
    lengths::Vector{Int}
    factors::Vector{MarginalizationFactor}
    base_nodes::Vector{Int}
    joint::Vector{EliminationStep}
    joint_leftovers::Vector{Int}
    prior::Vector{EliminationStep}
    prior_leftovers::Vector{Int}
end

# The largest table a plan may create. Beyond it the frontier recursion is used.
const _MAX_ELIMINATION_TABLE_LENGTH = 1 << 20

# Latents whose support is fixed by their type and shape, not by the values of their
# parents, so their domain can be fixed when the plan is built.
_has_fixed_support(dist) = dist isa Union{Distributions.Bernoulli,Distributions.Categorical}

_table_length(scope, domains) = prod(v -> length(domains[v]), scope; init=1)

"""
    _plan_variable_elimination(model)

Build the `VariableEliminationPlan` for a model whose marginalization cache is set, or
return `nothing` when variable elimination does not apply and the frontier recursion
should be used: a latent whose support could depend on its parents' values, a continuous
parameter missing from the parameter layout, or a table larger than
`_MAX_ELIMINATION_TABLE_LENGTH`.
"""
function _plan_variable_elimination(model)
    gd = model.graph_evaluation_data
    mc = model.marginalization_cache
    env = model.evaluation_env
    n = length(gd.sorted_nodes)
    position = Dict(vn => i for (i, vn) in enumerate(gd.sorted_nodes))
    parents = [
        [position[p] for p in MetaGraphsNext.inneighbor_labels(model.g, vn)] for
        vn in gd.sorted_nodes
    ]

    # Node kinds, as in `_marginalize_recursive`.
    skip = falses(n)
    is_latent = falses(n)
    is_parameter = falses(n)
    for i in 1:n
        vt = gd.variable_types[i]
        if vt == GeneratedQuantity || vt == FixedParameter
            skip[i] = true
        elseif gd.is_stochastic_vals[i] && !gd.is_observed_vals[i]
            if mc.node_types[i] == :discrete_finite
                is_latent[i] = true
            else
                haskey(mc.param_offsets, gd.sorted_nodes[i]) || return nothing
                is_parameter[i] = true
            end
        end
    end
    latents = findall(is_latent)
    latent_id = Dict(i => k for (k, i) in enumerate(latents))
    domains = Vector{Vector{Int}}(undef, length(latents))
    for (k, i) in enumerate(latents)
        dist = gd.node_function_vals[i](env, gd.loop_vars_vals[i])
        _has_fixed_support(dist) || return nothing
        domains[k] = collect(Int, _enumerate_discrete_values(dist))
    end

    # Scope of each node's value, in topological order.
    value_scope = [Int[] for _ in 1:n]
    parent_scope(i) =
        sort!(unique!(reduce(vcat, (value_scope[p] for p in parents[i]); init=Int[])))
    passthrough = falses(n)
    for i in 1:n
        skip[i] && continue
        if is_latent[i]
            value_scope[i] = [latent_id[i]]
        elseif !gd.is_stochastic_vals[i]
            value_scope[i] = parent_scope(i)
        elseif is_parameter[i]
            scope = parent_scope(i)
            isempty(scope) && continue
            dist = gd.node_function_vals[i](env, gd.loop_vars_vals[i])
            if !Base.issingletontype(typeof(Bijectors.bijector(dist)))
                passthrough[i] = true
                value_scope[i] = scope
            end
        end
    end

    # Nodes `i` reads whose value depends on latents, transitively, in topological order.
    function recompute_set(i)
        seen = Set{Int}()
        stack = copy(parents[i])
        while !isempty(stack)
            p = pop!(stack)
            p in seen && continue
            push!(seen, p)
            if !is_latent[p] && !isempty(value_scope[p])
                append!(stack, parents[p])
            end
        end
        return sort!([p for p in seen if !is_latent[p] && !isempty(value_scope[p])])
    end

    factors = MarginalizationFactor[]
    base_nodes = Int[]
    for i in 1:n
        (skip[i] || !gd.is_stochastic_vals[i]) && continue
        scope = parent_scope(i)
        is_latent[i] && (scope = sort!(union(scope, latent_id[i])))
        if isempty(scope)
            push!(base_nodes, i)
            continue
        end
        _table_length(scope, domains) <= _MAX_ELIMINATION_TABLE_LENGTH || return nothing
        push!(
            factors,
            MarginalizationFactor(i, scope, recompute_set(i), !gd.is_observed_vals[i]),
        )
    end

    scopes = [f.scope for f in factors]
    joint = _elimination_steps(
        scopes, collect(eachindex(factors)), length(latents), domains
    )
    prior = _elimination_steps(
        scopes,
        [k for k in eachindex(factors) if factors[k].is_prior],
        length(latents),
        domains,
    )
    (joint === nothing || prior === nothing) && return nothing
    offsets = zeros(Int, n)
    lengths = zeros(Int, n)
    for i in findall(is_parameter)
        offsets[i] = mc.param_offsets[gd.sorted_nodes[i]]
        lengths[i] = mc.param_lengths[gd.sorted_nodes[i]]
    end
    return VariableEliminationPlan(
        latents,
        domains,
        passthrough,
        offsets,
        lengths,
        factors,
        base_nodes,
        joint...,
        prior...,
    )
end

"""
    _elimination_steps(scopes, initial_slots, n_latents, domains)

Eliminate the latents in reverse topological order, the last latent first. For each, the
tables that depend on it are combined and it is summed out. Returns the steps and the slots
left at the end (all with an empty scope), or `nothing` if a table would exceed
`_MAX_ELIMINATION_TABLE_LENGTH`.

Eliminating latents from the last to the first is the backward pass of the forward-backward
algorithm on a chain, and is optimal on trees. On other graphs a better order may exist; the
table size limit sends such models to the frontier recursion.
"""
function _elimination_steps(scopes, initial_slots, n_latents, domains)
    slot_scope = Dict{Int,Vector{Int}}(s => scopes[s] for s in initial_slots)
    slots_with = [Int[] for _ in 1:n_latents]
    for s in initial_slots, v in scopes[s]
        push!(slots_with[v], s)
    end
    next_slot = length(scopes) + 1
    steps = EliminationStep[]
    for v in n_latents:-1:1
        inputs = sort!([s for s in slots_with[v] if haskey(slot_scope, s)])
        isempty(inputs) && continue
        scope = sort!(unique!(reduce(vcat, (slot_scope[s] for s in inputs))))
        _table_length(scope, domains) <= _MAX_ELIMINATION_TABLE_LENGTH || return nothing
        shapes = map(inputs) do s
            [u in slot_scope[s] ? length(domains[u]) : 1 for u in scope]
        end
        push!(steps, EliminationStep(v, inputs, shapes, scope, next_slot))
        foreach(s -> delete!(slot_scope, s), inputs)
        output_scope = filter(!=(v), scope)
        slot_scope[next_slot] = output_scope
        for u in output_scope
            push!(slots_with[u], next_slot)
        end
        next_slot += 1
    end
    return steps, sort!(collect(keys(slot_scope)))
end

#######################
# Evaluation
#######################

_nan_to_neginf(x) = isnan(x) ? oftype(x, -Inf) : x

# Continuous parameter `i`'s value and log-Jacobian from its slice of the parameter vector.
function _parameter_value(plan, dist, i, x)
    start = plan.offsets[i]
    b_inv = Bijectors.inverse(Bijectors.bijector(dist))
    slice = view(x, start:(start + plan.lengths[i] - 1))
    return Bijectors.with_logabsdet_jacobian(b_inv, reconstruct(b_inv, dist, slice))
end

# The term node `i` adds to the log joint, with `NaN` treated as `-Inf` as in
# `_marginalize_recursive`.
function _node_term(plan, model, env, i, x)
    gd = model.graph_evaluation_data
    vn = gd.sorted_nodes[i]
    dist = gd.node_function_vals[i](env, gd.loop_vars_vals[i])
    if plan.offsets[i] == 0
        # An observation, or a latent at the value set in `env`.
        return _nan_to_neginf(logpdf(dist, AbstractPPL.getvalue(env, vn)))
    end
    value, logjac = _parameter_value(plan, dist, i, x)
    logp = logpdf(dist, value)
    return isnan(logp) ? oftype(logp, -Inf) : logp + logjac
end

function _recompute(plan, model, env, i, x)
    gd = model.graph_evaluation_data
    vn = gd.sorted_nodes[i]
    value = gd.node_function_vals[i](env, gd.loop_vars_vals[i])
    if plan.passthrough[i]
        value = first(_parameter_value(plan, value, i, x))
    end
    return BangBang.setindex!!(env, value, vn)
end

# The table of factor `f`: its term for every configuration of its scope.
function _factor_table(plan, model, env, f::MarginalizationFactor, x)
    sorted_nodes = model.graph_evaluation_data.sorted_nodes
    dims = Tuple(length(plan.domains[v]) for v in f.scope)
    table = nothing
    for (k, I) in enumerate(CartesianIndices(dims))
        for (d, v) in enumerate(f.scope)
            value = plan.domains[v][I[d]]
            env = BangBang.setindex!!(env, value, sorted_nodes[plan.latents[v]])
        end
        for r in f.recompute
            env = _recompute(plan, model, env, r, x)
        end
        term = _node_term(plan, model, env, f.node, x)
        # The table takes the type of its terms, widened if they differ (as under ReverseDiff).
        if table === nothing
            table = Array{typeof(term)}(undef, dims)
        elseif !(term isa eltype(table))
            table = convert(Array{promote_type(eltype(table), typeof(term))}, table)
        end
        table[k] = term
    end
    return table, env
end

# Sum the latents out of `tables` following `steps`, and add up what is left.
function _eliminate(steps, leftovers, tables)
    slots = Dict{Int,Any}(enumerate(tables))
    for step in steps
        combined = reduce(
            (a, b) -> a .+ b,
            (
                reshape(slots[s], shape...) for
                (s, shape) in zip(step.inputs, step.input_shapes)
            ),
        )
        dim = findfirst(==(step.latent), step.scope)
        slots[step.output] = dropdims(
            LogExpFunctions.logsumexp(combined; dims=dim); dims=dim
        )
    end
    return sum(slots[s][] for s in leftovers; init=0.0)
end

"""
    _evaluate_with_variable_elimination!!(model, plan, x; temperature=1.0)

The marginalized log densities of `model` at continuous parameters `x`, with the same
log prior / log likelihood split as `_marginalize_recursive`: the log prior sums the latents
out of the prior terms only, and the log likelihood is the log joint minus the log prior.
"""
function _evaluate_with_variable_elimination!!(
    model, plan::VariableEliminationPlan, x::AbstractVector; temperature=1.0
)
    env = _evaluate_continuous_model_parameters_with_values!!(
        model, x; transformed=model.transformed
    )
    gd = model.graph_evaluation_data
    base_prior, base_lik = 0.0, 0.0
    for i in plan.base_nodes
        term = _node_term(plan, model, env, i, x)
        if gd.is_observed_vals[i]
            base_lik += term
        else
            base_prior += term
        end
    end

    tables = Vector{Any}(undef, length(plan.factors))
    work_env = env
    for (k, f) in enumerate(plan.factors)
        tables[k], work_env = _factor_table(plan, model, work_env, f, x)
    end
    log_joint = base_prior + base_lik + _eliminate(plan.joint, plan.joint_leftovers, tables)
    log_prior = base_prior + _eliminate(plan.prior, plan.prior_leftovers, tables)
    log_lik = isfinite(log_prior) ? log_joint - log_prior : log_joint
    return env,
    (
        logprior=log_prior,
        loglikelihood=log_lik,
        tempered_logjoint=log_prior + temperature * log_lik,
    )
end
