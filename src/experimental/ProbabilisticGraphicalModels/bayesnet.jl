"""
    BayesianNetwork

A structure representing a Bayesian Network.
"""
struct BayesianNetwork{V,T,F}
    graph::SimpleDiGraph{T}
    "names of the variables in the network"
    names::Vector{V}
    "mapping from variable names to ids"
    names_to_ids::Dict{V,T}
    "values of each variable in the network"
    values::Dict{V,Any} # TODO: make it a NamedTuple for better performance in the future
    "distributions of the stochastic variables"
    distributions::Vector{Distribution}
    "deterministic functions of the deterministic variables"
    deterministic_functions::Vector{F}
    "ids of the stochastic variables"
    stochastic_ids::Vector{T}
    "ids of the deterministic variables"
    deterministic_ids::Vector{T}
    is_stochastic::BitVector
    is_observed::BitVector
end

function BayesianNetwork{V}() where {V}
    return BayesianNetwork(
        SimpleDiGraph{Int}(), # by default, vertex ids are integers
        V[],
        Dict{V,Int}(),
        Dict{V,Any}(),
        Distribution[],
        Any[],
        Int[],
        Int[],
        BitVector(),
        BitVector(),
    )
end

"""
    condition(bn::BayesianNetwork{V}, values::Dict{V,Any}) where {V}

Condition the Bayesian Network on the values of some variables. Return a new Bayesian Network with the conditioned graph.
"""
function condition(
    bn::BayesianNetwork{V}, conditioning_variables_and_values::Dict{V,<:Any}
) where {V}
    is_observed = copy(bn.is_observed)
    values = copy(bn.values)
    bn_new = BangBang.setproperties!!(bn; is_observed=is_observed, values=values)
    return condition!(bn_new, conditioning_variables_and_values)
end

"""
    condition!(bn::BayesianNetwork{V}, values::Dict{V,Any}) where {V}

Condition the Bayesian Network on the values of some variables. Mutating version of [`condition`](@ref).
"""
function condition!(
    bn::BayesianNetwork{V}, conditioning_variables_and_values::Dict{V,<:Any}
) where {V}
    for (name, value) in conditioning_variables_and_values
        id = bn.names_to_ids[name]
        if !bn.is_stochastic[id]
            throw(ArgumentError("Variable $name is not stochastic, cannot condition on it"))
        elseif bn.is_observed[id]
            @warn "Variable $name is already observed, overwriting its value"
        else
            bn.is_observed[id] = true
        end
        bn.values[name] = value
    end
    return bn
end

function decondition(bn::BayesianNetwork{V}) where {V}
    conditioned_variables_ids = findall(bn.is_observed)
    return decondition(bn, bn.names[conditioned_variables_ids])
end

function decondition!(bn::BayesianNetwork{V}) where {V}
    conditioned_variables_ids = findall(bn.is_observed)
    return decondition!(bn, bn.names[conditioned_variables_ids])
end

function decondition(bn::BayesianNetwork{V}, variables::Vector{V}) where {V}
    is_observed = copy(bn.is_observed)
    values = copy(bn.values)
    bn_new = BangBang.setproperties!!(bn; is_observed=is_observed, values=values)
    return decondition!(bn_new, variables)
end

function decondition!(bn::BayesianNetwork{V}, deconditioning_variables::Vector{V}) where {V}
    for name in deconditioning_variables
        id = bn.names_to_ids[name]
        if !bn.is_stochastic[id]
            throw(
                ArgumentError("Variable $name is not stochastic, cannot decondition on it")
            )
        elseif !bn.is_observed[id]
            throw(ArgumentError("Variable $name is not observed, cannot decondition on it"))
        end
        bn.is_observed[id] = false
        delete!(bn.values, name)
    end
    return bn
end

"""
    add_stochastic_vertex!(bn::BayesianNetwork{V}, name::V, dist::Distribution, is_observed::Bool) where {V}

Adds a stochastic vertex with name `name` and distribution `dist` to the Bayesian Network. Returns the id of the added vertex
if successful, 0 otherwise.
"""
function add_stochastic_vertex!(
    bn::BayesianNetwork{V,T}, name::V, dist::Distribution, is_observed::Bool
)::T where {V,T}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.distributions, dist)
    push!(bn.is_stochastic, true)
    push!(bn.is_observed, is_observed)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.stochastic_ids, id)
    return id
end

"""
    add_deterministic_vertex!(bn::BayesianNetwork{V}, name::V, f::F) where {V,F}

Adds a deterministic vertex with name `name` and deterministic function `f` to the Bayesian Network. Returns the id of the added vertex
if successful, 0 otherwise.
"""
function add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F)::T where {T,V,F}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.deterministic_functions, f)
    push!(bn.is_stochastic, false)
    push!(bn.is_observed, false)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.deterministic_ids, id)
    return id
end

"""
    add_edge!(bn::BayesianNetwork{V}, from::V, to::V) where {V}

Adds an edge between two vertices in the Bayesian Network. Returns true if successful, false otherwise.
"""
function add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V)::Bool where {T,V}
    from_id = bn.names_to_ids[from]
    to_id = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end

"""
    ancestral_sampling(bn::BayesianNetwork{V}) where {V}

Perform ancestral sampling on a Bayesian network to generate one sample from the joint distribution.

Ancestral sampling works by:
1. Finding a topological ordering of the nodes
2. Sampling from each node in order, using the already-sampled parent values for conditional distributions

### Return Value
The function returns a `Dict{V, Any}` where:
- Each key is a variable name (of type `V`) in the Bayesian Network.
- Each value is the sampled value for that variable, which can be of any type (`Any`).

This dictionary represents a single sample from the joint distribution of the Bayesian Network, capturing the dependencies and conditional relationships defined in the network structure.

"""
function ancestral_sampling(bn::BayesianNetwork{V}) where {V}
    ordered_vertices = Graphs.topological_sort_by_dfs(bn.graph)
    samples = Dict{V,Any}()

    for vertex_id in ordered_vertices
        vertex_name = bn.names[vertex_id]
        if bn.is_observed[vertex_id]
            samples[vertex_name] = bn.values[vertex_name]
            continue
        end
        if bn.is_stochastic[vertex_id]
            dist_idx = findfirst(id -> id == vertex_id, bn.stochastic_ids)
            samples[vertex_name] = rand(bn.distributions[dist_idx])
        else
            # deterministic node
            parent_ids = Graphs.inneighbors(bn.graph, vertex_id)
            parent_values = [samples[bn.names[pid]] for pid in parent_ids]
            func_idx = findfirst(id -> id == vertex_id, bn.deterministic_ids)
            samples[vertex_name] = bn.deterministic_functions[func_idx](parent_values...)
        end
    end

    return samples
end

"""
    is_conditionally_independent(bn::BayesianNetwork, X::V, Y::V[, Z::Vector{V}]) where {V}

Determines if two variables X and Y are conditionally independent given the conditioning information already known.
If Z is provided, the conditioning information in `bn` will be ignored.
"""
function is_conditionally_independent end

function is_conditionally_independent(bn::BayesianNetwork{V}, X::V, Y::V) where {V}
    # Use currently observed variables as Z
    Z = V[v for (v, is_obs) in zip(bn.names, bn.is_observed) if is_obs]
    return is_conditionally_independent(bn, X, Y, Z)
end

function is_conditionally_independent(
    bn::BayesianNetwork{V}, X::V, Y::V, Z::Vector{V}
) where {V}
    # Get vertex IDs
    x_id = bn.names_to_ids[X]
    y_id = bn.names_to_ids[Y]
    z_ids = Set([bn.names_to_ids[z] for z in Z])

    # Track visited nodes and their states
    n_vertices = nv(bn.graph)
    visited = falses(n_vertices)

    # Queue entries are (node_id, from_parent)
    queue = Tuple{Int,Bool}[]

    # Start from X
    push!(queue, (x_id, true))   # As if coming from parent
    push!(queue, (x_id, false))  # As if coming from child

    while !isempty(queue)
        current_id, from_parent = popfirst!(queue)

        if visited[current_id]
            continue
        end
        visited[current_id] = true

        # If we reached Y, path is active
        if current_id == y_id
            return false
        end

        is_conditioned = current_id in z_ids
        parents = inneighbors(bn.graph, current_id)
        children = outneighbors(bn.graph, current_id)

        # Case 1: Node is not conditioned
        if !is_conditioned
            # Can go to children if coming from parent or at start node
            if from_parent || current_id == x_id
                for child in children
                    push!(queue, (child, true))
                end
            end

            # Can go to parents if coming from child or at start node
            if !from_parent || current_id == x_id
                for parent in parents
                    push!(queue, (parent, false))
                end
            end
        end

        # Case 2: Node is conditioned or has conditioned descendants
        if is_conditioned || has_conditioned_descendant(bn, current_id, z_ids)
            # If this is a collider or descendant of collider
            if length(parents) > 1 || !isempty(children)
                # Can go to parents regardless of direction
                for parent in parents
                    push!(queue, (parent, false))
                end
            end
        end
    end

    return true
end

function has_conditioned_descendant(bn::BayesianNetwork, node_id::Int, z_ids::Set{Int})
    visited = falses(nv(bn.graph))
    queue = Int[node_id]

    while !isempty(queue)
        current = popfirst!(queue)

        if visited[current]
            continue
        end
        visited[current] = true

        if current in z_ids
            return true
        end

        # Add all unvisited children
        append!(queue, filter(c -> !visited[c], outneighbors(bn.graph, current)))
    end

    return false
end
