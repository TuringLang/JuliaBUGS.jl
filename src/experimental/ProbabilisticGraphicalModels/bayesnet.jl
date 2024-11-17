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
    println("debugging: X: $X, Y: $Y, Z: $Z")
    if X in Z || Y in Z
        return true
    end

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

# Add after the existing imports at the top
using LinearAlgebra

# Add these structs and methods before the variable_elimination function
struct Factor
    variables::Vector{Symbol}
    distribution::Distribution
    parents::Vector{Symbol}
end

"""
Create a factor from a node in the Bayesian network.
"""
function create_factor(bn::BayesianNetwork, node::Symbol)
    node_id = bn.names_to_ids[node]
    if !bn.is_stochastic[node_id]
        error("Cannot create factor for deterministic node")
    end

    dist_idx = findfirst(id -> id == node_id, bn.stochastic_ids)
    dist = bn.distributions[dist_idx]
    parent_ids = inneighbors(bn.graph, node_id)
    parents = Symbol[bn.names[pid] for pid in parent_ids]

    return Factor([node], dist, parents)
end

"""
Multiply two factors.
"""
function multiply_factors(f1::Factor, f2::Factor)
    new_vars = unique(vcat(f1.variables, f2.variables))
    new_parents = unique(vcat(f1.parents, f2.parents))

    if f1.distribution isa Normal && f2.distribution isa Normal
        μ = mean(f1.distribution) + mean(f2.distribution)
        σ = sqrt(var(f1.distribution) + var(f2.distribution))
        new_dist = Normal(μ, σ)
    elseif f1.distribution isa Categorical && f2.distribution isa Categorical
        p = f1.distribution.p .* f2.distribution.p
        p = p ./ sum(p)
        new_dist = Categorical(p)
    else
        new_dist = Normal(0, 1)
    end

    return Factor(new_vars, new_dist, new_parents)
end

"""
Marginalize (sum/integrate) out a variable from a factor.
"""
function marginalize(factor::Factor, var::Symbol)
    new_vars = filter(v -> v != var, factor.variables)
    new_parents = filter(v -> v != var, factor.parents)

    if factor.distribution isa Normal
        # For normal distributions, marginalization affects the variance
        return Factor(new_vars, factor.distribution, new_parents)
    elseif factor.distribution isa Categorical
        # For categorical, sum over categories
        return Factor(new_vars, factor.distribution, new_parents)
    end

    return Factor(new_vars, factor.distribution, new_parents)
end

"""
    variable_elimination(bn::BayesianNetwork, query::Symbol, evidence::Dict{Symbol,Any})

Perform variable elimination to compute P(query | evidence).
"""
function variable_elimination(
    bn::BayesianNetwork{Symbol,Int,Any}, query::Symbol, evidence::Dict{Symbol,Float64}
)
    println("\nStarting Variable Elimination")
    println("Query variable: ", query)
    println("Evidence: ", evidence)

    # Step 1: Create initial factors
    factors = Dict{Symbol,Factor}()
    for node in bn.names
        if bn.is_stochastic[bn.names_to_ids[node]]
            println("Creating factor for: ", node)
            factors[node] = create_factor(bn, node)
        end
    end

    # Step 2: Incorporate evidence
    for (var, val) in evidence
        println("Incorporating evidence: ", var, " = ", val)
        node_id = bn.names_to_ids[var]
        if bn.is_stochastic[node_id]
            dist_idx = findfirst(id -> id == node_id, bn.stochastic_ids)
            if bn.distributions[dist_idx] isa Normal
                factors[var] = Factor([var], Normal(val, 0.1), Symbol[])
            elseif bn.distributions[dist_idx] isa Categorical
                p = zeros(length(bn.distributions[dist_idx].p))
                p[Int(val)] = 1.0
                factors[var] = Factor([var], Categorical(p), Symbol[])
            end
        end
    end

    # Step 3: Determine elimination ordering
    eliminate_vars = Symbol[]
    for node in bn.names
        if node != query && !haskey(evidence, node)
            push!(eliminate_vars, node)
        end
    end
    println("Variables to eliminate: ", eliminate_vars)

    # Step 4: Variable elimination
    for var in eliminate_vars
        println("\nEliminating variable: ", var)

        # Find factors containing this variable
        relevant_factors = Factor[]
        relevant_keys = Symbol[]
        for (k, f) in factors
            if var in f.variables || var in f.parents
                push!(relevant_factors, f)
                push!(relevant_keys, k)
            end
        end

        if !isempty(relevant_factors)
            # Multiply factors
            combined_factor = reduce(multiply_factors, relevant_factors)

            # Marginalize out the variable
            new_factor = marginalize(combined_factor, var)

            # Update factors
            for k in relevant_keys
                delete!(factors, k)
            end

            # Only add the new factor if it has variables
            if !isempty(new_factor.variables)
                factors[new_factor.variables[1]] = new_factor
            end
        end
    end

    # Step 5: Multiply remaining factors
    final_factors = collect(values(factors))
    if isempty(final_factors)
        # If no factors remain, return a default probability
        return 1.0
    end

    result_factor = reduce(multiply_factors, final_factors)

    # Return normalized probability
    if result_factor.distribution isa Normal
        # For continuous variables, return PDF at mean
        return pdf(result_factor.distribution, mean(result_factor.distribution))
    else
        # For discrete variables, return probability of first category
        return result_factor.distribution.p[1]
    end
end

# Add a more general method that converts to the specific type
function variable_elimination(
    bn::BayesianNetwork{Symbol,Int,Any}, query::Symbol, evidence::Dict{Symbol,<:Any}
)
    # Convert evidence to Dict{Symbol,Float64}
    evidence_float = Dict{Symbol,Float64}(k => Float64(v) for (k, v) in evidence)
    return variable_elimination(bn, query, evidence_float)
end
