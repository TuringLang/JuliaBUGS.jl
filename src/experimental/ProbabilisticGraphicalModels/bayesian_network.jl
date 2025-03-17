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
    evaluation_env::NamedTuple
    loop_vars::Dict{V,NamedTuple}
    "distributions of the stochastic variables"
    distributions::Vector{F}
    "deterministic functions of the deterministic variables"
    deterministic_functions::Vector{F}
    "ids of the stochastic variables"
    stochastic_ids::Vector{T}
    "ids of the deterministic variables"
    deterministic_ids::Vector{T}
    is_stochastic::BitVector
    is_observed::BitVector
    node_types::Vector{Symbol}            # e.g. :discrete or :continuous
    "transformed variable lengths for each variable"
    transformed_var_lengths::Dict{V,Int}
    "total length of transformed parameters"
    transformed_param_length::Int
end

function BayesianNetwork{V}() where {V}
    return BayesianNetwork(
        SimpleDiGraph{Int}(), # by default, vertex ids are integers
        V[],
        Dict{V,Int}(),
        (;),    # Empty NamedTuple for evaluation_env
        Dict{V,NamedTuple}(),
        Any[],
        Any[],
        Int[],
        Int[],
        BitVector(),
        BitVector(),
        Symbol[],
        Dict{V,Int}(),  # Empty Dict for transformed_var_lengths
        0,              # transformed_param_length
    )
end

"""
    translate_BUGSGraph_to_BayesianNetwork(g::MetaGraph; init=Dict{Symbol,Any}())

Translates a BUGSGraph (with node metadata stored in NodeInfo) into a BayesianNetwork.
"""
function translate_BUGSGraph_to_BayesianNetwork(
    g::JuliaBUGS.BUGSGraph, evaluation_env, model=nothing
)
    # Retrieve variable labels (stored as VarNames) from g.
    varnames = collect(labels(g))
    n = length(varnames)
    original_graph = g.graph

    # Preallocate arrays/dictionaries.
    names = Vector{VarName}(undef, n)
    names_to_ids = Dict{VarName,Int}()
    loop_vars = Dict{VarName,NamedTuple}()
    distributions = Vector{Function}(undef, n)
    deterministic_fns = Vector{Function}(undef, n)
    stochastic_ids = Int[]
    deterministic_ids = Int[]
    is_stochastic = falses(n)
    is_observed = falses(n)
    node_types = Vector{Symbol}(undef, n)
    transformed_var_lengths = Dict{VarName,Int}()
    transformed_param_length = 0

    if model !== nothing
        if isdefined(model, :transformed_var_lengths)
            for (k, v) in pairs(model.transformed_var_lengths)
                transformed_var_lengths[k] = v
            end
        end
        if isdefined(model, :transformed_param_length)
            transformed_param_length = model.transformed_param_length
        end
    end

    for (i, varname) in enumerate(varnames)
        nodeinfo = g[varname]
        names[i] = varname
        names_to_ids[varname] = i
        is_stochastic[i] = nodeinfo.is_stochastic
        is_observed[i] = nodeinfo.is_observed
        loop_vars[varname] = nodeinfo.loop_vars

        if nodeinfo.is_stochastic
            distributions[i] = nodeinfo.node_function
            push!(stochastic_ids, i)
            node_types[i] = :stochastic
        else
            deterministic_fns[i] = nodeinfo.node_function
            push!(deterministic_ids, i)
            node_types[i] = :deterministic
        end
    end

    bn = BayesianNetwork(
        SimpleDiGraph{Int}(n),
        names,
        names_to_ids,
        evaluation_env,
        loop_vars,
        distributions,
        deterministic_fns,
        stochastic_ids,
        deterministic_ids,
        is_stochastic,
        is_observed,
        node_types,
        transformed_var_lengths,
        transformed_param_length,
    )

    # Add edges using the BayesianNetwork's mapping.
    for e in edges(original_graph)
        let src_name = bn.names[e.src]
            let dst_name = bn.names[e.dst]
                add_edge!(bn, src_name, dst_name)
            end
        end
    end

    return bn
end

"""
    add_stochastic_vertex!(bn::BayesianNetwork{V,T}, name::V, dist::Any, node_type::Symbol; is_observed::Bool=false) where {V,T}

Add a stochastic vertex with name `name`, a distribution object/function `dist`,
and a declared node_type (`:discrete` or `:continuous`).
"""
function add_stochastic_vertex!(
    bn::BayesianNetwork{V,T},
    name::V,
    dist::Any,
    is_observed::Bool=false,
    node_type::Symbol=:continuous,
)::T where {V,T}
    Graphs.add_vertex!(bn.graph) || return 0
    id = nv(bn.graph)
    push!(bn.distributions, dist)
    push!(bn.is_stochastic, true)
    push!(bn.is_observed, is_observed)
    push!(bn.names, name)
    bn.names_to_ids[name] = id
    push!(bn.stochastic_ids, id)
    push!(bn.node_types, node_type)
    return id
end

"""
    add_deterministic_vertex!(bn::BayesianNetwork{V,T}, name::V, f::F) where {T,V,F}

Add a deterministic vertex.
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
    push!(bn.node_types, :deterministic)
    return id
end

"""
    add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V) where {T,V}

Add a directed edge from `from` -> `to`.
"""
function add_edge!(bn::BayesianNetwork{V,T}, from::V, to::V)::Bool where {T,V}
    from_id = bn.names_to_ids[from]
    to_id = bn.names_to_ids[to]
    return Graphs.add_edge!(bn.graph, from_id, to_id)
end

function evaluate(bn::BayesianNetwork)
    logp = 0.0
    evaluation_env = bn.evaluation_env

    for (i, varname) in enumerate(bn.names)
        is_stochastic = bn.is_stochastic[i]
        if is_stochastic
            dist_fn = bn.distributions[i](evaluation_env, bn.loop_vars[varname])

            value = AbstractPPL.get(evaluation_env, varname)
            bijector = Bijectors.bijector(dist_fn)
            value_transformed = Bijectors.transform(bijector, value)

            logpdf_val = Distributions.logpdf(dist_fn, value)
            logjac = Bijectors.logabsdetjac(Bijectors.inverse(bijector), value_transformed)
            logp += logpdf_val + logjac

        else
            fn = bn.deterministic_functions[i](evaluation_env, bn.loop_vars[varname])
            evaluation_env = BangBang.setindex!!(evaluation_env, fn, varname)
        end
    end
    return evaluation_env, logp
end

function evaluate_with_values(bn::BayesianNetwork, parameter_values::AbstractVector)
    bugsmodel_node_order = [bn.names[i] for i in topological_sort_by_dfs(bn.graph)]
    var_lengths = bn.transformed_var_lengths

    evaluation_env = deepcopy(bn.evaluation_env)
    current_idx = 1
    logprior, loglikelihood = 0.0, 0.0

    for vn in bugsmodel_node_order
        i = bn.names_to_ids[vn]

        is_stochastic = bn.is_stochastic[i]
        is_observed = bn.is_observed[i]

        if !is_stochastic
            value = bn.deterministic_functions[i](evaluation_env, bn.loop_vars[vn])
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        else
            if !is_observed
                dist = bn.distributions[i](evaluation_env, bn.loop_vars[vn])
                b = Bijectors.bijector(dist)
                # If the variable is not in transformed_var_lengths, calculate it
                if !haskey(var_lengths, vn)
                    var_value = AbstractPPL.get(evaluation_env, vn)
                    transformed_value = Bijectors.transform(b, var_value)
                    var_lengths[vn] = length(transformed_value)
                end
                l = var_lengths[vn]
                b_inv = Bijectors.inverse(b)
                reconstructed_value = JuliaBUGS.reconstruct(
                    b_inv, dist, view(parameter_values, current_idx:(current_idx + l - 1))
                )
                value, logjac = Bijectors.with_logabsdet_jacobian(
                    b_inv, reconstructed_value
                )

                current_idx += l
                logprior += logpdf(dist, value) + logjac
                evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
            else
                dist = bn.distributions[i](evaluation_env, bn.loop_vars[vn])
                loglikelihood += logpdf(dist, AbstractPPL.get(evaluation_env, vn))
            end
        end
    end

    return evaluation_env, logprior + loglikelihood
end

"""
    enumerate_discrete_values(dist)

Return all possible values for a discrete distribution.
"""
function enumerate_discrete_values(dist::DiscreteUnivariateDistribution)
    if dist isa Categorical
        return 1:length(dist.p)
    elseif dist isa Bernoulli
        return [0, 1]
    elseif dist isa Binomial
        return 0:(dist.n)
    elseif dist isa Poisson
        # For Poisson, we need to truncate at some reasonable point #TODO: We are currently not using this 
        λ = dist.λ
        # Use 3 standard deviations (sqrt(λ)) as a heuristic cutoff
        max_value = ceil(Int, λ + 3 * sqrt(λ))
        return 0:max_value
    elseif dist isa DiscreteUniform
        return (dist.a):(dist.b)
    else
        # For other distributions, sample a reasonable set of values
        # This is a fallback and might not be optimal
        support_values = support(dist)
        if support_values isa UnitRange
            return support_values
        else
            # Sample some values and deduplicate
            samples = rand(dist, 100)
            return unique(samples)
        end
    end
end

function evaluate_with_marginalization(
    bn::BayesianNetwork{V,T,F}, parameter_values::AbstractVector
) where {V,T,F}
    bugsmodel_node_order = [bn.names[i] for i in topological_sort_by_dfs(bn.graph)]
    var_lengths = bn.transformed_var_lengths

    discrete_vars = V[]
    for id in topological_sort_by_dfs(bn.graph)
        if bn.is_stochastic[id] && bn.node_types[id] == :discrete && !bn.is_observed[id]
            push!(discrete_vars, bn.names[id])
        end
    end

    if isempty(discrete_vars)
        return evaluate_with_values(bn, parameter_values)
    end

    current_idx = 1

    function recursive_marginalize(assignments::Dict{<:Any,Any}, var_idx::Int)
        if var_idx > length(discrete_vars)
            local_idx = current_idx

            temp_env = deepcopy(bn.evaluation_env)

            for (var, value) in assignments
                temp_env = BangBang.setindex!!(temp_env, value, var)
            end

            logprior, loglikelihood = 0.0, 0.0

            for vn in bugsmodel_node_order
                i = bn.names_to_ids[vn]

                is_stochastic = bn.is_stochastic[i]
                is_observed = bn.is_observed[i]
                is_discrete = bn.node_types[i] == :discrete

                if vn in keys(assignments)
                    continue
                end

                if !is_stochastic
                    # Handle deterministic nodes
                    value = bn.deterministic_functions[i](temp_env, bn.loop_vars[vn])
                    temp_env = BangBang.setindex!!(temp_env, value, vn)
                else
                    # Handle stochastic nodes
                    dist = bn.distributions[i](temp_env, bn.loop_vars[vn])

                    if !is_observed
                        if !is_discrete
                            # Handle continuous variables using parameter_values
                            b = Bijectors.bijector(dist)

                            # If the variable is not in transformed_var_lengths, calculate it
                            if !haskey(var_lengths, vn)
                                var_value = AbstractPPL.get(temp_env, vn)
                                transformed_value = Bijectors.transform(b, var_value)
                                var_lengths[vn] = length(transformed_value)
                            end

                            l = var_lengths[vn]
                            b_inv = Bijectors.inverse(b)

                            # Use parameter_values for continuous variables
                            reconstructed_value = JuliaBUGS.reconstruct(
                                b_inv,
                                dist,
                                view(parameter_values, local_idx:(local_idx + l - 1)),
                            )

                            value, logjac = Bijectors.with_logabsdet_jacobian(
                                b_inv, reconstructed_value
                            )

                            local_idx += l
                            logprior += logpdf(dist, value) + logjac
                            temp_env = BangBang.setindex!!(temp_env, value, vn)
                        end
                        # Note: discrete variables handled by marginalization are skipped here
                    else
                        # Handle observed variables
                        loglikelihood += logpdf(dist, AbstractPPL.get(temp_env, vn))
                    end
                end
            end

            # Calculate joint probability of discrete variables
            discrete_logprob = 0.0
            for (var, value) in assignments
                var_id = bn.names_to_ids[var]
                dist = bn.distributions[var_id](temp_env, bn.loop_vars[var])
                discrete_logprob += logpdf(dist, value)
            end

            # Return combined probability
            return exp(logprior + loglikelihood + discrete_logprob)
        end

        # Get current discrete variable
        current_var = discrete_vars[var_idx]
        var_id = bn.names_to_ids[current_var]

        # Create temporary environment to get distribution
        temp_env = deepcopy(bn.evaluation_env)

        # Set all previously assigned variables
        for (var, value) in assignments
            temp_env = BangBang.setindex!!(temp_env, value, var)
        end

        # Update deterministic nodes that might affect the distribution
        for i in topological_sort_by_dfs(bn.graph)
            vn = bn.names[i]
            # Skip if already assigned or if it's the current variable
            if vn in keys(assignments) || vn == current_var
                continue
            end

            if !bn.is_stochastic[i]
                value = bn.deterministic_functions[i](temp_env, bn.loop_vars[vn])
                temp_env = BangBang.setindex!!(temp_env, value, vn)
            end
        end

        # Get distribution for this variable
        dist = bn.distributions[var_id](temp_env, bn.loop_vars[current_var])

        # Get possible values for this variable
        possible_values = enumerate_discrete_values(dist)

        # Initialize total probability
        total_prob = 0.0

        # Sum over all possible values
        for val in possible_values
            # Create new assignment dictionary
            new_assignments = copy(assignments)
            new_assignments[current_var] = val

            # Recursive call for next variable
            prob = recursive_marginalize(new_assignments, var_idx + 1)

            # Add to total probability
            total_prob += prob
        end

        return total_prob
    end

    # Start recursion with empty assignments
    total_prob = recursive_marginalize(Dict{Any,Any}(), 1)

    return bn.evaluation_env, log(total_prob)
end

"""
NOTE: THIS FUNCTION IS EXPERIMENTAL

    evaluate_with_marginalization_dp_experimental(bn::BayesianNetwork, parameter_values::AbstractVector)

Evaluates a Bayesian network using dynamic programming for marginalization over discrete variables,
while using parameter values for continuous variables.
"""
function evaluate_with_marginalization_dp_experimental(
    bn::BayesianNetwork, parameter_values::AbstractVector
)
    bugsmodel_node_order = [bn.names[i] for i in topological_sort_by_dfs(bn.graph)]
    var_lengths = bn.transformed_var_lengths

    # Identify discrete variables in topological order
    sorted_ids = topological_sort_by_dfs(bn.graph)
    discrete_vars = []

    for id in sorted_ids
        if bn.is_stochastic[id] && bn.node_types[id] == :discrete && !bn.is_observed[id]
            push!(discrete_vars, bn.names[id])
        end
    end

    # If no discrete variables, just use the standard evaluation
    if isempty(discrete_vars)
        return evaluate_with_values(bn, parameter_values)
    end

    # Memoization cache - key is variable index and current assignments
    memo = Dict{Tuple{Int,String},Float64}()

    # Recursive function with memoization
    function recursive_marginalize(assignments::Dict{Any,Any}, var_idx::Int, param_idx::Int)
        # Create a cache key: (variable index, parameter index, serialized assignments)
        # We serialize assignments to make it hashable
        assignment_str = join(
            ["$k:$v" for (k, v) in sort(collect(assignments); by=x -> string(x[1]))], ","
        )
        cache_key = (var_idx, assignment_str)

        # Check if result is already in cache
        if haskey(memo, cache_key)
            return memo[cache_key], param_idx
        end

        # Base case: all discrete variables assigned
        if var_idx > length(discrete_vars)
            # Create a local copy of parameter index
            local_idx = param_idx

            # Create environment with discrete variables set
            temp_env = deepcopy(bn.evaluation_env)

            # Set the discrete variables from assignments
            for (var, value) in assignments
                temp_env = BangBang.setindex!!(temp_env, value, var)
            end

            # Initialize logprior and loglikelihood
            logprior, loglikelihood = 0.0, 0.0

            # Process all nodes in topological order
            for vn in bugsmodel_node_order
                i = bn.names_to_ids[vn]

                is_stochastic = bn.is_stochastic[i]
                is_observed = bn.is_observed[i]
                is_discrete = bn.node_types[i] == :discrete

                # Skip variables that have already been assigned
                if vn in keys(assignments)
                    continue
                end

                if !is_stochastic
                    # Handle deterministic nodes
                    value = bn.deterministic_functions[i](temp_env, bn.loop_vars[vn])
                    temp_env = BangBang.setindex!!(temp_env, value, vn)
                else
                    # Handle stochastic nodes
                    dist = bn.distributions[i](temp_env, bn.loop_vars[vn])

                    if !is_observed
                        if !is_discrete
                            # Handle continuous variables using parameter_values
                            b = Bijectors.bijector(dist)

                            # If the variable is not in transformed_var_lengths, calculate it
                            if !haskey(var_lengths, vn)
                                var_value = AbstractPPL.get(temp_env, vn)
                                transformed_value = Bijectors.transform(b, var_value)
                                var_lengths[vn] = length(transformed_value)
                            end

                            l = var_lengths[vn]
                            b_inv = Bijectors.inverse(b)

                            # Use parameter_values for continuous variables
                            reconstructed_value = JuliaBUGS.reconstruct(
                                b_inv,
                                dist,
                                view(parameter_values, local_idx:(local_idx + l - 1)),
                            )

                            value, logjac = Bijectors.with_logabsdet_jacobian(
                                b_inv, reconstructed_value
                            )

                            local_idx += l
                            logprior += logpdf(dist, value) + logjac
                            temp_env = BangBang.setindex!!(temp_env, value, vn)
                        end
                        # Note: discrete variables handled by marginalization are skipped here
                    else
                        # Handle observed variables
                        loglikelihood += logpdf(dist, AbstractPPL.get(temp_env, vn))
                    end
                end
            end

            # Calculate discrete variable probabilities
            discrete_logprob = 0.0
            for (var, value) in assignments
                var_id = bn.names_to_ids[var]
                dist = bn.distributions[var_id](temp_env, bn.loop_vars[var])
                discrete_logprob += logpdf(dist, value)
            end

            # Total log probability
            total_logp = logprior + loglikelihood + discrete_logprob

            # Return probability in non-log space
            result = exp(total_logp)

            # Cache and return the result
            memo[cache_key] = result
            return result, local_idx
        end

        # Get current discrete variable
        current_var = discrete_vars[var_idx]
        var_id = bn.names_to_ids[current_var]

        # Create temporary environment to get distribution
        temp_env = deepcopy(bn.evaluation_env)

        # Set all previously assigned variables
        for (var, value) in assignments
            temp_env = BangBang.setindex!!(temp_env, value, var)
        end

        # Update deterministic nodes that might affect the distribution
        for id in sorted_ids
            vn = bn.names[id]
            # Skip if already assigned or if it's the current variable
            if vn in keys(assignments) || vn == current_var
                continue
            end

            if !bn.is_stochastic[id]
                value = bn.deterministic_functions[id](temp_env, bn.loop_vars[vn])
                temp_env = BangBang.setindex!!(temp_env, value, vn)
            end
        end

        # Get distribution
        dist = bn.distributions[var_id](temp_env, bn.loop_vars[current_var])
        possible_values = enumerate_discrete_values(dist)

        # Sum over possible values
        total_prob = 0.0
        final_param_idx = param_idx  # Track final parameter index

        for val in possible_values
            new_assignments = copy(assignments)
            new_assignments[current_var] = val

            # Call recursive function, passing along param_idx
            prob, next_param_idx = recursive_marginalize(
                new_assignments, var_idx + 1, param_idx
            )

            total_prob += prob

            # Update final_param_idx for the first iteration only
            # This ensures we correctly advance the parameter index
            if val == possible_values[1]
                final_param_idx = next_param_idx
            end
        end

        # Cache and return result
        memo[cache_key] = total_prob
        return total_prob, final_param_idx
    end

    # Start recursion with empty assignments and initial parameter index
    total_prob, _ = recursive_marginalize(Dict{Any,Any}(), 1, 1)

    return bn.evaluation_env, log(total_prob)
end
