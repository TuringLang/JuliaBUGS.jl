import AbstractPPL: condition, decondition
using AbstractPPL: AbstractPPL, VarName, @varname
using BangBang
using JuliaBUGS: BUGSModel, BUGSGraph, _markov_blanket, labels

"""
    condition(model::BUGSModel, conditioning_spec; 
              create_subgraph::Bool=true,
              sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing)

Create a new model by conditioning on specified variables with given values.

This function:
1. Updates the evaluation environment with conditioned values
2. Marks conditioned variables as observed in the graph
3. Optionally creates a subgraph containing only relevant variables

# Arguments
- `model::BUGSModel`: The model to condition
- `conditioning_spec`: Variables and values to condition on

# Supported Input Formats
- `Dict{Symbol/VarName, Any}`: Dictionary of variable-value pairs
- `Vector{Symbol/VarName}`: Variables to condition (uses existing values from model)
- `Pairs...`: Variable-value pairs (e.g., `:x => 1.0, :y => 2.0`)
- `NamedTuple`: Named tuple of values (e.g., `(; x=1.0, y=2.0)`)

# Keywords
- `create_subgraph::Bool=true`: Whether to create a subgraph containing only the Markov blanket
- `sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing`: Pre-computed sorted nodes for efficiency

# Returns
- `BUGSModel`: A new model with specified variables conditioned

# Notes
- Only stochastic variables can be conditioned (not logical/deterministic nodes)
- Variables already marked as observed will generate a warning
- The returned model has updated `g` and `evaluation_env` fields

# Examples
```julia
# Dictionary input
model_cond = condition(model, Dict(:x => 1.0, :y => [2.0, 3.0]))

# Vector input (use current values)
model_cond = condition(model, [:x, :y])

# Pairs syntax
model_cond = condition(model, :x => 1.0, :y => 2.0)

# NamedTuple syntax
model_cond = condition(model, (; x=1.0, y=2.0))

# Skip subgraph creation for performance
model_cond = condition(model, Dict(:x => 1.0), create_subgraph=false)
```
"""
function condition(
    model::BUGSModel,
    conditioning_spec;
    create_subgraph::Bool=true,
    sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing,
)
    # Parse the conditioning specification
    var_values = parse_conditioning_spec(conditioning_spec, model)
    vars_to_condition = collect(keys(var_values))

    # Validate the variables
    check_conditioning_validity(model, vars_to_condition)

    # Update evaluation environment
    new_evaluation_env = update_evaluation_env(model.evaluation_env, var_values)

    # Mark variables as observed in the graph
    new_graph = mark_as_observed(model.g, vars_to_condition)

    # Create the conditioned model
    if create_subgraph
        # Compute new parameters (removing conditioned variables), maintaining order
        new_parameters = filter(vn -> vn ∉ vars_to_condition, model.parameters)

        # Compute Markov blanket and create subgraph
        markov_blanket_nodes = union(
            _markov_blanket(new_graph, new_parameters), new_parameters
        )

        # Filter sorted nodes
        sorted_blanket_nodes = if sorted_nodes === nothing
            filter(
                vn -> vn in markov_blanket_nodes,
                model.flattened_graph_node_data.sorted_nodes,
            )
        else
            filter(vn -> vn in markov_blanket_nodes, sorted_nodes)
        end

        # Create new model with subgraph
        return BUGSModel(
            model, new_graph, new_parameters, sorted_blanket_nodes, new_evaluation_env
        )
    else
        # Create new model without subgraph (keeping all nodes), maintaining order
        new_parameters = filter(vn -> vn ∉ vars_to_condition, model.parameters)
        return BUGSModel(
            model.transformed,
            model.untransformed_param_length,
            model.transformed_param_length,
            model.untransformed_var_lengths,
            model.transformed_var_lengths,
            new_evaluation_env,
            new_parameters,
            model.flattened_graph_node_data,
            new_graph,
            model.base_model,
            model.evaluation_mode,
            model.log_density_computation_function,
            model.model_def,
            model.data,
        )
    end
end

# Backward compatibility overload
function condition(model::BUGSModel, d::Dict{<:VarName,<:Any}, sorted_nodes=nothing)
    return condition(model, d; sorted_nodes=sorted_nodes)
end

# Handle multiple dispatch for different input types
function condition(model::BUGSModel, pairs::Pair{Symbol}...; kwargs...)
    dict = Dict{VarName,Any}()
    for (sym, val) in pairs
        dict[@varname($(sym))] = val
    end
    return condition(model, dict; kwargs...)
end

"""
    parse_conditioning_spec(spec, model::BUGSModel) -> Dict{VarName, Any}

Parse various conditioning specification formats into a standardized dictionary.

# Arguments
- `spec`: The conditioning specification in one of the supported formats
- `model::BUGSModel`: The model (needed when spec is a Vector to get values)

# Supported Formats
- `Dict`: Direct dictionary (Symbol keys converted to VarName)
- `Vector`: Variables to condition (values taken from model.evaluation_env)
- `Pairs...`: Variable-value pairs
- `NamedTuple`: Named tuple of values

# Returns
- `Dict{VarName, Any}`: Standardized dictionary mapping variables to values
"""
function parse_conditioning_spec(spec::Dict, model::BUGSModel)
    # Convert Symbol keys to VarName if needed
    result = Dict{VarName,Any}()
    for (k, v) in spec
        vn = k isa Symbol ? (@varname($k)) : k
        result[vn] = v
    end
    return result
end

function parse_conditioning_spec(spec::Vector, model::BUGSModel)
    # Use current values from model's evaluation environment
    result = Dict{VarName,Any}()
    for var in spec
        vn = var isa Symbol ? (@varname($var)) : var
        result[vn] = AbstractPPL.get(model.evaluation_env, vn)
    end
    return result
end

function parse_conditioning_spec(spec::NamedTuple, model::BUGSModel)
    # Convert NamedTuple to Dict
    result = Dict{VarName,Any}()
    for (k, v) in pairs(spec)
        result[@varname($k)] = v
    end
    return result
end

"""
    mark_as_observed(g::BUGSGraph, vars::Vector{<:VarName}) -> BUGSGraph

Create a new graph with specified variables marked as observed.

# Arguments
- `g::BUGSGraph`: The original graph
- `vars::Vector{<:VarName}`: Variables to mark as observed

# Returns
- `BUGSGraph`: New graph with variables marked as observed

# Implementation Note
Creates a copy of the graph and updates the `is_observed` field for each variable's NodeInfo.
"""
function mark_as_observed(g::BUGSGraph, vars::Vector{<:VarName})
    new_g = copy(g)
    for vn in vars
        node_info = new_g[vn]
        if node_info.is_stochastic && !node_info.is_observed
            new_g[vn] = BangBang.setproperty!!(node_info, :is_observed, true)
        end
    end
    return new_g
end

"""
    update_evaluation_env(env::NamedTuple, var_values::Dict{VarName, Any}) -> NamedTuple

Update evaluation environment with new variable values using BangBang.setindex!!

# Arguments
- `env::NamedTuple`: Current evaluation environment
- `var_values::Dict{VarName, Any}`: New values for variables

# Returns
- `NamedTuple`: Updated evaluation environment
"""
function update_evaluation_env(env::NamedTuple, var_values::Dict{<:VarName,<:Any})
    new_env = env
    for (vn, value) in var_values
        new_env = BangBang.setindex!!(new_env, value, vn)
    end
    return new_env
end

"""
    check_conditioning_validity(model::BUGSModel, vars::Vector{<:VarName})

Check if variables can be conditioned in the model.

# Checks
- Variables exist in the model graph
- Variables are stochastic (not deterministic/logical)
- Variables are not already observed (warning only)

# Throws
- `ArgumentError`: If variable doesn't exist or is not stochastic

# Warnings
- Issues warning if variable is already observed
"""
function check_conditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    for vn in vars
        # Check if variable exists
        if vn ∉ labels(model.g)
            throw(ArgumentError("Variable $vn does not exist in the model"))
        end

        # Check if variable is stochastic
        node_info = model.g[vn]
        if !node_info.is_stochastic
            throw(
                ArgumentError(
                    "$vn is not a stochastic variable, conditioning on it is not supported"
                ),
            )
        end

        # Warn if already observed
        if node_info.is_observed
            @warn "$vn is already observed, conditioning on it may not have the expected effect"
        end
    end
end

"""
    subgraph(model::BUGSModel, keep_vars::Vector{<:VarName}; 
             include_markov_blanket::Bool=true, 
             include_deterministic_dependencies::Bool=true,
             sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing)

Create a subgraph of the model containing specified variables and their dependencies.

# Arguments
- `model::BUGSModel`: The model to create subgraph from
- `keep_vars::Vector{<:VarName}`: Variables that must be kept in the subgraph

# Keywords
- `include_markov_blanket::Bool=true`: Include Markov blanket of kept variables
- `include_deterministic_dependencies::Bool=true`: Include deterministic nodes on paths
- `sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing`: Pre-computed sorted nodes

# Returns
- `BUGSModel`: A new model containing only the subgraph

# Examples
```julia
# Create subgraph with only variable x and its Markov blanket
sub_model = subgraph(model, [:x])

# Create minimal subgraph without Markov blanket
sub_model = subgraph(model, [:x, :y], include_markov_blanket=false)
```
"""
function subgraph(model::BUGSModel, keep_vars::Vector{<:VarName}; 
                  include_markov_blanket::Bool=true, 
                  include_deterministic_dependencies::Bool=true,
                  sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing)
    
    # Determine which nodes to keep
    nodes_to_keep = if include_markov_blanket
        union(_markov_blanket(model.g, keep_vars), keep_vars)
    else
        Set(keep_vars)
    end
    
    # TODO: Handle include_deterministic_dependencies if needed
    
    # Filter sorted nodes
    filtered_sorted_nodes = if sorted_nodes === nothing
        filter(
            vn -> vn in nodes_to_keep,
            model.flattened_graph_node_data.sorted_nodes
        )
    else
        filter(vn -> vn in nodes_to_keep, sorted_nodes)
    end
    
    # Create new model with subgraph
    # Note: We keep the same graph structure but only use a subset of nodes
    return BUGSModel(
        model, model.g, keep_vars, filtered_sorted_nodes, model.evaluation_env
    )
end

"""
    decondition(model::BUGSModel, var_spec; 
                expand_subgraph::Bool=true,
                reset_values::Bool=false,
                sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing)

Create a new model by removing conditioning from specified variables.

This function is the opposite of `condition`:
1. Marks specified variables as unobserved in the graph
2. Adds them back to the parameters list
3. Optionally expands the model to include these variables and their Markov blanket
4. Optionally resets their values in the evaluation environment

# Arguments
- `model::BUGSModel`: The model to decondition
- `var_spec`: Variables to decondition

# Supported Input Formats
- `Vector{Symbol/VarName}`: Variables to decondition
- `Symbol`: Single variable to decondition  
- `VarName`: Single variable to decondition

# Keywords
- `expand_subgraph::Bool=true`: Whether to expand the model to include Markov blanket of deconditioned variables
- `reset_values::Bool=false`: Whether to reset values to base model values (if available)
- `sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing`: Pre-computed sorted nodes for efficiency

# Returns
- `BUGSModel`: A new model with specified variables deconditioned

# Notes
- Only observed stochastic variables can be deconditioned
- If the model has a base_model, values can be reset from there
- The returned model has updated `g`, `parameters`, and optionally `evaluation_env` fields

# Examples
```julia
# Decondition a single variable
model_decond = decondition(model, :x)

# Decondition multiple variables
model_decond = decondition(model, [:x, :y])

# Decondition and reset to base model values
model_decond = decondition(model, [:x], reset_values=true)

# Decondition without expanding subgraph
model_decond = decondition(model, [:x], expand_subgraph=false)
```

# See Also
- [`condition`](@ref): Add conditioning to variables
- [`subgraph`](@ref): Create a subgraph without conditioning changes
"""
function decondition(model::BUGSModel, var_spec; 
                    expand_subgraph::Bool=true,
                    reset_values::Bool=false,
                    sorted_nodes::Union{Vector{<:VarName},Nothing}=nothing)
    
    # Parse the deconditioning specification
    vars_to_decondition = parse_deconditioning_spec(var_spec)
    
    # Validate the variables can be deconditioned
    check_deconditioning_validity(model, vars_to_decondition)
    
    # Mark variables as unobserved in the graph
    new_graph = mark_as_unobserved(model.g, vars_to_decondition)
    
    # Add variables back to parameters, maintaining order from sorted_nodes
    base_sorted_nodes = (model.base_model !== nothing ? model.base_model : model).flattened_graph_node_data.sorted_nodes
    all_potential_params = union(model.parameters, vars_to_decondition)
    new_parameters = filter(vn -> vn in all_potential_params, base_sorted_nodes)
    
    # Handle evaluation environment
    new_evaluation_env = if reset_values && model.base_model !== nothing
        # Reset values from base model
        reset_evaluation_env(model.evaluation_env, vars_to_decondition, model.base_model.evaluation_env)
    else
        # Keep current values
        model.evaluation_env
    end
    
    # Create the deconditioned model
    if expand_subgraph
        # Compute Markov blanket including the newly deconditioned variables
        markov_blanket_nodes = union(
            _markov_blanket(new_graph, new_parameters), 
            new_parameters
        )
        
        # Filter sorted nodes
        sorted_blanket_nodes = if sorted_nodes === nothing
            filter(
                vn -> vn in markov_blanket_nodes,
                (model.base_model !== nothing ? model.base_model : model).flattened_graph_node_data.sorted_nodes
            )
        else
            filter(vn -> vn in markov_blanket_nodes, sorted_nodes)
        end
        
        # Create new model with expanded subgraph
        return BUGSModel(
            model, new_graph, new_parameters, sorted_blanket_nodes, new_evaluation_env
        )
    else
        # Create new model without expanding subgraph
        return BUGSModel(
            model.transformed,
            model.untransformed_param_length,
            model.transformed_param_length,
            model.untransformed_var_lengths,
            model.transformed_var_lengths,
            new_evaluation_env,
            new_parameters,
            model.flattened_graph_node_data,
            new_graph,
            model.base_model,
            model.evaluation_mode,
            model.log_density_computation_function,
            model.model_def,
            model.data,
        )
    end
end

"""
    parse_deconditioning_spec(spec) -> Vector{VarName}

Parse various deconditioning specification formats into a standardized vector.

# Arguments
- `spec`: The deconditioning specification in one of the supported formats

# Supported Formats
- `Vector{Symbol/VarName}`: Variables to decondition
- `Symbol`: Single variable to decondition
- `VarName`: Single variable to decondition

# Returns
- `Vector{VarName}`: Standardized vector of variables to decondition
"""
function parse_deconditioning_spec(spec::Vector)
    return [var isa Symbol ? (@varname($var)) : var for var in spec]
end

function parse_deconditioning_spec(spec::Symbol)
    return [(@varname($spec))]
end

function parse_deconditioning_spec(spec::VarName)
    return [spec]
end

"""
    check_deconditioning_validity(model::BUGSModel, vars::Vector{<:VarName})

Check if variables can be deconditioned in the model.

# Checks
- Variables exist in the model graph
- Variables are stochastic (not deterministic/logical)
- Variables are currently observed

# Throws
- `ArgumentError`: If variable doesn't exist, is not stochastic, or is not observed
"""
function check_deconditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    for vn in vars
        # Check if variable exists
        if vn ∉ labels(model.g)
            throw(ArgumentError("Variable $vn does not exist in the model"))
        end
        
        # Check if variable is stochastic
        node_info = model.g[vn]
        if !node_info.is_stochastic
            throw(ArgumentError(
                "$vn is not a stochastic variable, deconditioning it is not supported"
            ))
        end
        
        # Check if variable is currently observed
        if !node_info.is_observed
            throw(ArgumentError(
                "$vn is not currently observed, cannot decondition an unobserved variable"
            ))
        end
    end
end

"""
    mark_as_unobserved(g::BUGSGraph, vars::Vector{<:VarName}) -> BUGSGraph

Create a new graph with specified variables marked as unobserved.

# Arguments
- `g::BUGSGraph`: The original graph
- `vars::Vector{<:VarName}`: Variables to mark as unobserved

# Returns
- `BUGSGraph`: New graph with variables marked as unobserved

# Implementation Note
Creates a copy of the graph and updates the `is_observed` field for each variable's NodeInfo.
"""
function mark_as_unobserved(g::BUGSGraph, vars::Vector{<:VarName})
    new_g = copy(g)
    for vn in vars
        node_info = new_g[vn]
        if node_info.is_stochastic && node_info.is_observed
            new_g[vn] = BangBang.setproperty!!(node_info, :is_observed, false)
        end
    end
    return new_g
end

"""
    reset_evaluation_env(env::NamedTuple, vars::Vector{<:VarName}, base_env::NamedTuple) -> NamedTuple

Reset specified variables in evaluation environment to values from base environment.

# Arguments
- `env::NamedTuple`: Current evaluation environment
- `vars::Vector{<:VarName}`: Variables to reset
- `base_env::NamedTuple`: Base evaluation environment to get values from

# Returns
- `NamedTuple`: Updated evaluation environment with reset values
"""
function reset_evaluation_env(env::NamedTuple, vars::Vector{<:VarName}, base_env::NamedTuple)
    new_env = env
    for vn in vars
        try
            base_value = AbstractPPL.get(base_env, vn)
            new_env = BangBang.setindex!!(new_env, base_value, vn)
        catch
            # Variable doesn't exist in base_env, skip it
            continue
        end
    end
    return new_env
end
