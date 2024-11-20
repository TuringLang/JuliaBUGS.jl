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
    is_conditionally_independent(bn::BayesianNetwork, X::Vector{V}, Y::Vector{V}, Z::Vector{V}) where {V}

Test whether sets of variables X and Y are conditionally independent given set Z in a Bayesian Network using the Bayes Ball algorithm.

# Arguments
- `bn::BayesianNetwork`: The Bayesian Network structure
- `X::Vector{V}`: First set of variables to test for independence
- `Y::Vector{V}`: Second set of variables to test for independence
- `Z::Vector{V}`: Set of conditioning variables (can be empty)

# Returns
- `true`: if X and Y are conditionally independent given Z (X ⊥ Y | Z)
- `false`: if X and Y are conditionally dependent given Z

# Description
The Bayes Ball algorithm determines conditional independence by checking if there exists an active path between 
variables in X and Y given Z. The algorithm follows these rules:
- In a chain (A → B → C): B blocks the path if conditioned
- In a fork (A ← B → C): B blocks the path if conditioned
- In a collider (A → B ← C): B opens the path if conditioned 
# Examples
```
"""
function is_conditionally_independent(
    bn::BayesianNetwork{V}, X::Vector{V}, Y::Vector{V}, Z::Vector{V}
) where {V}
    isempty(X) && throw(ArgumentError("X cannot be empty"))
    isempty(Y) && throw(ArgumentError("Y cannot be empty"))

    x_ids = Set([bn.names_to_ids[x] for x in X])
    y_ids = Set([bn.names_to_ids[y] for y in Y])
    z_ids = Set([bn.names_to_ids[z] for z in Z])

    # Check if any variable in X or Y is in Z
    if !isempty(intersect(x_ids, z_ids)) || !isempty(intersect(y_ids, z_ids))
        return true
    end

    # Add observed variables to conditioning set
    for (id, is_obs) in enumerate(bn.is_observed)
        if is_obs
            push!(z_ids, id)
        end
    end

    # Track visited nodes and their directions
    n_vertices = nv(bn.graph)
    visited_up = falses(n_vertices)   # Visited going up (from child to parent)
    visited_down = falses(n_vertices) # Visited going down (from parent to child)

    # Queue entries are (node_id, going_up)
    queue = Tuple{Int,Bool}[]

    # Start from all X nodes
    for x_id in x_ids
        push!(queue, (x_id, true))   # Try going up
        push!(queue, (x_id, false))  # Try going down
    end

    while !isempty(queue)
        current_id, going_up = popfirst!(queue)

        # Skip if we've visited this node in this direction
        if (going_up && visited_up[current_id]) || (!going_up && visited_down[current_id])
            continue
        end

        # Mark as visited in current direction
        if going_up
            visited_up[current_id] = true
        else
            visited_down[current_id] = true
        end

        # If we reached a Y node, path is active
        if current_id in y_ids
            return false
        end

        is_conditioned = current_id in z_ids
        parents = inneighbors(bn.graph, current_id)
        children = outneighbors(bn.graph, current_id)

        if is_conditioned
            # If conditioned:
            # - In a chain/fork: blocks the path
            # - In a collider or descendant of collider: allows going up to parents
            if length(parents) > 1 || !isempty(children)  # Is collider or has children
                for parent in parents
                    push!(queue, (parent, true))  # Can only go up to parents
                end
            end
        else
            # If not conditioned:
            if going_up
                # Going up: can visit parents
                for parent in parents
                    push!(queue, (parent, true))
                end
            else
                # Going down: can visit children
                for child in children
                    push!(queue, (child, false))
                end
            end

            # At starting nodes (X), we can go both up and down
            if current_id in x_ids
                if going_up
                    for child in children
                        push!(queue, (child, false))
                    end
                else
                    for parent in parents
                        push!(queue, (parent, true))
                    end
                end
            end
        end
    end

    return true
end

# Single variable version with Z
function is_conditionally_independent(
    bn::BayesianNetwork{V}, X::V, Y::V, Z::Vector{V}
) where {V}
    return is_conditionally_independent(bn, [X], [Y], Z)
end
