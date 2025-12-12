"""
AbstractPPL interface implementation for JuliaBUGS models.

This module provides:
1. Conditioning API - condition/decondition variables in models
2. Evaluation API - evaluate models with different parameter values

Organization:
- Public API functions (condition, decondition, evaluate!!)
- Conditioning helpers (parsing, validation, variable expansion)
- Graph modification helpers (marking observation status)
- Model traversal helpers (base model access, parameter calculation)
- Model creation helpers (regenerating log density functions)
"""

import AbstractPPL: condition, decondition, evaluate!!

#######################
# Conditioning API
#######################

"""
    condition(model::BUGSModel, conditioning_spec)

Create a new model by conditioning on specified variables with given values.
The returned model uses `UseGraph` evaluation mode. To use optimized log density
computation, call `set_evaluation_mode(model, UseGeneratedLogDensityFunction())`.

# Arguments
- `model::BUGSModel`: The model to condition
- `conditioning_spec`: Variables and values to condition on
  - `Dict{VarName, Any}`: Variable-value pairs
  - `Vector{VarName}`: Variables to condition (uses current values)
  - `NamedTuple`: For simple variable names (e.g., `(; x=1.0, y=2.0)`)

# Requirements
- Variables must be stochastic (not logical/deterministic)
- Values must be compatible with variable constraints
- If a variable doesn't exist but subsumes others (e.g., `v` subsumes `v[1], v[2]`), 
  all subsumed variables will be conditioned with a warning

# Returns
New `BUGSModel` with:
- Conditioned variables marked as observed and removed from parameters
- Updated parameter lengths and evaluation environment
- Original model unchanged (immutable)

# Examples
```jldoctest condition
julia> model_def = @bugs begin
           for i in 1:3
               x[i] ~ Normal(0, 1)
           end
           y ~ Normal(sum(x[:]), 1)
       end;

julia> model = compile(model_def, (;));

julia> # Basic conditioning
       model_cond = condition(model, Dict(@varname(x[1]) => 1.0, @varname(x[2]) => 2.0));

julia> model_cond.evaluation_env.x[1:2]
2-element Vector{Float64}:
 1.0
 2.0

julia> parameters(model_cond)
2-element Vector{VarName}:
 x[3]
 y

julia> # Conditioning with subsumption (will warn and condition all x[i])
       model_cond2 = @test_logs(
           (:warn, "Variable x does not exist in the model. Conditioning on subsumed variables instead: x[1], x[2], x[3]"),
           condition(model, Dict(@varname(x) => [5.0, 6.0, 7.0]))
       );

julia> model_cond2.evaluation_env.x
3-element Vector{Float64}:
 5.0
 6.0
 7.0

julia> parameters(model_cond2)  # All x[i] removed, only y remains
1-element Vector{VarName}:
 y

julia> # Check parameter lengths
       model.untransformed_param_length  # Original has 4 parameters
4

julia> model_cond.untransformed_param_length  # After conditioning x[1], x[2]
2

julia> model_cond2.untransformed_param_length  # After conditioning all x[i]
1

julia> # NamedTuple syntax
       model_cond3 = condition(model, (; y=10.0));

julia> model_cond3.evaluation_env.y
10.0

julia> sort(parameters(model_cond3); by=string)  # y removed, only x[i] remain
3-element Vector{VarName}:
 x[1]
 x[2]
 x[3]

julia> # Error cases
       try
           condition(model, Dict(@varname(z) => 1.0))
       catch e
           println(e)
       end
ArgumentError("Variable z does not exist in the model")

julia> # Using vector of VarNames (conditions using current values)
       model_init = initialize!(model, (; x=[1.0, 2.0, 3.0], y=4.0));

julia> model_cond4 = condition(model_init, [@varname(x[1]), @varname(x[3])]);

julia> model_cond4.evaluation_env.x[[1, 3]]
2-element Vector{Float64}:
 1.0
 3.0

julia> parameters(model_cond4)
2-element Vector{VarName}:
 x[2]
 y
```
"""
function condition(model::BUGSModel, conditioning_spec)
    # Parse and validate conditioning specification
    var_values = _parse_conditioning_spec(conditioning_spec, model)::Dict{<:VarName,<:Any}
    vars_to_condition = collect(keys(var_values))::Vector{<:VarName}

    # Expand and validate variables (handles subsumption)
    expanded_vars, expanded_var_values = _prepare_conditioning_vars(
        model, vars_to_condition, var_values
    )

    # Update evaluation environment with new values
    new_evaluation_env = _update_evaluation_env(model.evaluation_env, expanded_var_values)

    # Mark variables as observed in the graph
    new_graph = _mark_as_observed(model.g, expanded_vars)

    # Create updated model with conditioned variables
    # Log density function will be generated when set_evaluation_mode is called with UseGeneratedLogDensityFunction
    return _create_modified_model(
        model,
        new_graph,
        new_evaluation_env;
        base_model=isnothing(model.base_model) ? model : model.base_model,
    )
end

#######################
# Conditioning Helpers
#######################

# Parse different types of conditioning specifications into a standard format
function _parse_conditioning_spec(spec::Dict{<:VarName,<:Any}, model::BUGSModel)
    # Dict already has VarName keys, just return it
    return spec
end
function _parse_conditioning_spec(spec::Vector{<:VarName}, model::BUGSModel)
    # Use current values from model's evaluation environment
    result = Dict{VarName,Any}()
    for vn in spec
        result[vn] = AbstractPPL.get(model.evaluation_env, vn)
    end
    return result
end
function _parse_conditioning_spec(spec::NamedTuple, model::BUGSModel)
    # Convert NamedTuple to Dict
    result = Dict{VarName,Any}()
    for (k, v) in pairs(spec)
        result[VarName{k}()] = v
    end
    return result
end

# Generic function to mark variables' observation status
function _mark_observation_status(g::BUGSGraph, vars::Vector{<:VarName}, observed::Bool)
    new_g = copy(g)
    for vn in vars
        node_info = new_g[vn]
        if node_info.is_stochastic && node_info.is_observed != observed
            new_g[vn] = BangBang.setproperty!!(node_info, :is_observed, observed)
        end
    end
    return new_g
end

function _mark_as_observed(g::BUGSGraph, vars::Vector{<:VarName})
    return _mark_observation_status(g, vars, true)
end

function _update_evaluation_env(env::NamedTuple, var_values::Dict{<:VarName,<:Any})
    new_env = env
    for (vn, value) in var_values
        new_env = BangBang.setindex!!(new_env, value, vn)
    end
    return new_env
end

# Validate and expand variables for conditioning
function _check_conditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    expanded_vars = _expand_subsumed_vars(
        model, vars, "Conditioning on subsumed variables instead"
    )

    _validate_stochastic_vars(model, expanded_vars, "conditioning")

    # Warn about already observed variables
    for vn in expanded_vars
        if model.g[vn].is_observed
            @warn "$vn is already observed, conditioning on it may not have the expected effect"
        end
    end

    return expanded_vars
end

"""
    decondition(model::BUGSModel[, vars_to_decondition::Vector{VarName}])

Restore observed variables back to being parameters.

# Arguments
- `model::BUGSModel`: The model with conditioned variables
- `vars_to_decondition::Vector{VarName}` (optional): Specific variables to decondition
  - If provided: Deconditions only the specified variables
  - If omitted: Restores to base_model structure (requires model to have base_model)

# Requirements
For specific variables:
- Variables must exist in the model and be currently observed stochastic variables
- Cannot decondition variables that were observed in the original data
- Cannot decondition logical/deterministic variables

For base_model restoration (no args):
- Model must have a `base_model` (i.e., must be a conditioned model)
- Throws error if model has no base_model

# Returns
- With vars specified: New `BUGSModel` with specified variables restored as parameters
- Without vars: New model with base_model's structure but current evaluation environment

# Examples
```jldoctest decondition
julia> model_def = @bugs begin
           x ~ dnorm(0, 1)
           y ~ dnorm(x, 1) 
           z ~ dnorm(y, 1)
       end;

julia> model = compile(model_def, (; z = 2.5));

julia> # Condition model
       model_cond = condition(model, (; x = 1.0, y = 1.5));

julia> parameters(model_cond)
VarName[]

julia> # Partial deconditioning with specified variables
       model_d1 = decondition(model_cond, [@varname(y)]);

julia> parameters(model_d1)
1-element Vector{VarName}:
 y

julia> # Full restoration to base model (no arguments)
       model_restored = decondition(model_cond);

julia> parameters(model_restored) == parameters(model)
true

julia> model_restored.evaluation_env.x  # Keeps conditioned values
1.0

julia> model_restored.evaluation_env.y
1.5

julia> # Error when no base_model
       try
           decondition(model)  # Original model has no base_model
       catch e
           println(e)
       end
ArgumentError("This is a unconditioned model. Use decondition(model, vars) to specify variables to decondition.")

julia> # Cannot decondition original data
       try
           decondition(model_cond, [@varname(z)])
       catch e
           println(e)
       end
ArgumentError("Cannot decondition z: it was observed in the original data")

julia> # Chain of conditioning
       m1 = condition(model, (; x = 1.0));
       m2 = condition(m1, (; y = 2.0));

julia> # With flat design, all conditioned models restore to original
       model_restored = decondition(m2);

julia> parameters(model_restored) == parameters(model)  # Back to original
true

julia> model_restored.evaluation_env.x  # But keeps the conditioned values
1.0

julia> model_restored.evaluation_env.y
2.0

julia> # m1 also restores to original model
       parameters(decondition(m1)) == parameters(model)
true

julia> # Subsumption example
       model_arr = compile(@bugs(begin
           for i in 1:3
               v[i] ~ dnorm(0, 1)
           end
       end), (;));

julia> model_arr_cond = @test_logs(
           (:warn, "Variable v does not exist in the model. Conditioning on subsumed variables instead: v[1], v[2], v[3]"),
           condition(model_arr, Dict(@varname(v) => [1.0, 2.0, 3.0]))
       );

julia> # Decondition with subsumption
       model_arr_decon = @test_logs(
           (:warn, "Variable v does not exist in the model. Deconditioning subsumed observed variables instead: v[1], v[2], v[3]"),
           decondition(model_arr_cond, [@varname(v)])
       );

julia> sort(parameters(model_arr_decon); by=string)
3-element Vector{VarName}:
 v[1]
 v[2]
 v[3]
```
"""
function decondition(model::BUGSModel)
    if isnothing(model.base_model)
        throw(
            ArgumentError(
                "This is a unconditioned model. Use decondition(model, vars) to specify variables to decondition.",
            ),
        )
    end

    return BangBang.setproperty!!(model.base_model, :evaluation_env, model.evaluation_env)
end

function decondition(model::BUGSModel, vars_to_decondition::Vector{<:VarName})
    # Expand variables if they subsume others
    expanded_vars = _expand_vars_for_deconditioning(model, vars_to_decondition)

    # Check validity of variables to decondition
    _check_deconditioning_validity(model, expanded_vars)

    # Mark variables as unobserved in the graph
    new_graph = _mark_as_unobserved(model.g, expanded_vars)

    # Create updated model with deconditioned variables
    return _create_modified_model(model, new_graph, model.evaluation_env)
end

# Expand variables for deconditioning (handle subsumption)
function _expand_vars_for_deconditioning(model::BUGSModel, vars::Vector{<:VarName})
    # For deconditioning, we need to filter for observed stochastic variables
    filter_fn = label -> model.g[label].is_observed && model.g[label].is_stochastic

    return _expand_subsumed_vars(
        model,
        vars,
        "Deconditioning subsumed observed variables instead";
        filter_fn=filter_fn,
    )
end

# Validate variables for deconditioning
function _check_deconditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    _validate_stochastic_vars(model, vars, "deconditioning")

    # Get original observed variables
    original_model = _get_base_model(model)
    original_observed = _get_observed_stochastic_vars(original_model)

    for vn in vars
        node_info = model.g[vn]

        if !node_info.is_observed
            throw(ArgumentError("$vn is not currently observed, cannot decondition"))
        end

        if vn in original_observed
            throw(
                ArgumentError(
                    "Cannot decondition $vn: it was observed in the original data"
                ),
            )
        end
    end
end

# Common validation for stochastic variables
function _validate_stochastic_vars(
    model::BUGSModel, vars::Vector{<:VarName}, operation::String
)
    for vn in vars
        if vn ∉ labels(model.g)
            throw(ArgumentError("Variable $vn does not exist in the model"))
        end

        if !model.g[vn].is_stochastic
            throw(
                ArgumentError(
                    "$vn is not a stochastic variable, $operation is not supported"
                ),
            )
        end
    end
end

function _mark_as_unobserved(g::BUGSGraph, vars::Vector{<:VarName})
    return _mark_observation_status(g, vars, false)
end

#######################
# Model Traversal Helpers
#######################

# Get the base (original) model by traversing the chain
function _get_base_model(model::BUGSModel)
    original_model = model
    while !isnothing(original_model.base_model)
        original_model = original_model.base_model
    end
    return original_model
end

# Common helper function to get observed stochastic variables
function _get_observed_stochastic_vars(model::BUGSModel)
    observed_vars = Set{VarName}()
    for vn in labels(model.g)
        node_info = model.g[vn]
        if node_info.is_stochastic && node_info.is_observed
            push!(observed_vars, vn)
        end
    end
    return observed_vars
end

# Common helper function to calculate parameter lengths
function _calculate_param_lengths(model::BUGSModel, parameters::Vector{<:VarName})
    untransformed_length = sum(
        model.untransformed_var_lengths[vn] for vn in parameters; init=0
    )
    transformed_length = sum(model.transformed_var_lengths[vn] for vn in parameters; init=0)
    return untransformed_length, transformed_length
end

#######################
# Variable Expansion Helpers
#######################

# Expand variables that subsume others (e.g., x subsumes x[1], x[2], ...)
function _expand_subsumed_vars(
    model::BUGSModel,
    vars::Vector{<:VarName},
    warning_message::String;
    filter_fn::Function=label -> true,
)
    expanded_vars = VarName[]

    for vn in vars
        if vn ∉ labels(model.g)
            # Check if there are any variables in the model that are subsumed by vn
            subsumed_vars = [
                label for label in labels(model.g) if
                AbstractPPL.subsumes(vn, label) && filter_fn(label)
            ]

            if !isempty(subsumed_vars)
                # Warn user and expand to subsumed variables
                sorted_vars = sort(string.(subsumed_vars))
                @warn "Variable $vn does not exist in the model. $warning_message: $(join(sorted_vars, ", "))"
                append!(expanded_vars, subsumed_vars)
            else
                # Variable doesn't exist and has no subsumed variables
                throw(ArgumentError("Variable $vn does not exist in the model"))
            end
        else
            push!(expanded_vars, vn)
        end
    end

    return unique(expanded_vars)  # Remove duplicates
end

# Helper function to prepare conditioning variables (handles subsumption)
function _prepare_conditioning_vars(
    model::BUGSModel, vars::Vector{<:VarName}, var_values::Dict{<:VarName,<:Any}
)
    expanded_vars = _check_conditioning_validity(model, vars)

    # If vars were expanded due to subsumption, update var_values accordingly
    if length(expanded_vars) > length(vars)
        expanded_var_values = Dict{VarName,Any}()
        for vn in expanded_vars
            if haskey(var_values, vn)
                expanded_var_values[vn] = var_values[vn]
            else
                # Find the original var that subsumes this one
                for (orig_vn, val) in var_values
                    if AbstractPPL.subsumes(orig_vn, vn)
                        # Extract the appropriate value for indexed variables
                        expanded_var_values[vn] = AbstractPPL.getoptic(vn)(val)
                        break
                    end
                end
            end
        end
        return expanded_vars, expanded_var_values
    else
        return expanded_vars, var_values
    end
end

# Helper function to create a modified model with updated graph and environment
function _create_modified_model(
    model::BUGSModel,
    new_graph::BUGSGraph,
    new_evaluation_env::NamedTuple;
    base_model=nothing,
)
    # Create new graph evaluation data
    new_graph_evaluation_data = GraphEvaluationData(new_graph)
    new_parameters = new_graph_evaluation_data.sorted_parameters

    # Calculate new parameter lengths
    new_untransformed_param_length, new_transformed_param_length = _calculate_param_lengths(
        model, new_parameters
    )

    # Recompute mutable symbols for the new graph
    new_mutable_symbols = get_mutable_symbols(new_graph_evaluation_data)

    # Create the new model with all updated fields
    # IMPORTANT: Invalidate all caches when graph structure changes
    # - Log density function is regenerated on-demand when switching to UseGeneratedLogDensityFunction
    # - Auto-marginalization cache is recomputed on-demand when switching to UseAutoMarginalization
    kwargs = Dict{Symbol,Any}(
        :untransformed_param_length => new_untransformed_param_length,
        :transformed_param_length => new_transformed_param_length,
        :evaluation_env => new_evaluation_env,
        :graph_evaluation_data => new_graph_evaluation_data,
        :g => new_graph,
        :log_density_computation_function => nothing,  # Invalidate: graph changed
        :marginalization_cache => nothing,  # Invalidate: graph changed
        :mutable_symbols => new_mutable_symbols,
        :evaluation_mode => UseGraph(),  # Reset to safe default
    )

    # Add base_model if provided
    if !isnothing(base_model)
        kwargs[:base_model] = base_model
    end

    # Return model without precomputing (on-demand generation for all modes)
    return BUGSModel(model; kwargs...)
end

# Common helper function to regenerate log density function
function _regenerate_log_density_function(
    model_def::Expr,
    graph::BUGSGraph,
    evaluation_env::NamedTuple,
    graph_evaluation_data::GraphEvaluationData,
)
    lowered_model_def, reconstructed_model_def = JuliaBUGS._generate_lowered_model_def(
        model_def, graph, evaluation_env
    )

    if !isnothing(lowered_model_def)
        log_density_computation_expr = JuliaBUGS._gen_log_density_computation_function_expr(
            lowered_model_def, evaluation_env, gensym(:__compute_log_density__)
        )
        new_log_density_computation_function = Core.eval(
            JuliaBUGS, log_density_computation_expr
        )

        # Collect sorted nodes from the reconstructed model def to ensure correct parameter ordering
        pass = JuliaBUGS.CollectSortedNodes(evaluation_env)
        JuliaBUGS.analyze_block(pass, reconstructed_model_def)

        # Filter to only include nodes that are in the graph
        sorted_nodes = filter(pass.sorted_nodes) do node
            node in graph_evaluation_data.sorted_nodes
        end

        # Update graph evaluation data with the correct sorted nodes
        updated_graph_evaluation_data = GraphEvaluationData(graph, sorted_nodes)

        return new_log_density_computation_function, updated_graph_evaluation_data
    else
        return nothing, graph_evaluation_data
    end
end

#######################
# Observed Value Updates
#######################

"""
    set_observed_values!(model::BUGSModel, obs::Dict{<:VarName,<:Any})

Update values of observed stochastic variables without reconditioning or regenerating code.

Validates that each variable exists in the model, is stochastic, and is currently observed.
Updates the evaluation environment in place and returns the updated model.
"""
function set_observed_values!(model::BUGSModel, obs::Dict{<:VarName,<:Any})
    new_env = model.evaluation_env
    for (vn, val) in obs
        if vn ∉ labels(model.g)
            throw(ArgumentError("Variable $vn does not exist in the model"))
        end
        node_info = model.g[vn]
        if !node_info.is_stochastic
            throw(ArgumentError("Cannot update $vn: it is deterministic (logical)"))
        end
        if !node_info.is_observed
            throw(ArgumentError("Cannot update $vn: it is not observed"))
        end
        new_env = BangBang.setindex!!(new_env, val, vn)
    end
    return BangBang.setproperty!!(model, :evaluation_env, new_env)
end

"""
    regenerate_log_density_function(model::BUGSModel; force::Bool=false)

Generate and attach a compiled log-density function for the model's current graph and evaluation environment.

Does not change the evaluation mode. When `force=false`, preserves an existing compiled function; when `force=true`,
overwrites it if a new one can be generated. Returns the updated model (or the original if generation is not possible).
"""
function regenerate_log_density_function(model::BUGSModel; force::Bool=false)
    new_fn, updated_graph_eval_data = _regenerate_log_density_function(
        model.model_def, model.g, model.evaluation_env, model.graph_evaluation_data
    )
    # Always refresh graph_evaluation_data from regeneration helper (it may refine ordering)
    model = BangBang.setproperty!!(model, :graph_evaluation_data, updated_graph_eval_data)

    if isnothing(new_fn)
        # Cannot generate compiled function; leave as-is
        return model
    end

    if force || isnothing(model.log_density_computation_function)
        model = BangBang.setproperty!!(model, :log_density_computation_function, new_fn)
    end
    return model
end

#######################
# Evaluation API
#######################

"""
    AbstractPPL.evaluate!!(rng::Random.AbstractRNG, model::BUGSModel; sample_observed=false)

Evaluate model using ancestral sampling from the given RNG.

# Arguments
- `rng`: Random number generator for sampling
- `model`: The BUGSModel to evaluate
- `sample_observed`: If true, sample observed nodes; if false (default), keep observed data fixed. Latent variables are always sampled.
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether to compute log density in transformed space (default model.transformed)

# Returns
- `evaluation_env`: Updated evaluation environment
- `logp`: Log joint density (uses model.transformed to determine if transformed space)
"""
function evaluate!!(
    rng::Random.AbstractRNG,
    model::BUGSModel;
    sample_observed=false,
    temperature=1.0,
    transformed=model.transformed,
)
    evaluation_env, log_densities = evaluate_with_rng!!(
        rng,
        model;
        sample_observed=sample_observed,
        temperature=temperature,
        transformed=transformed,
    )
    return evaluation_env, log_densities.tempered_logjoint
end

"""
    AbstractPPL.evaluate!!(model::BUGSModel; temperature=1.0, transformed=model.transformed)

Evaluate model using current values in the evaluation environment.

# Arguments
- `model`: The BUGSModel to evaluate
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether to compute log density in transformed space (default model.transformed)

# Returns
- `evaluation_env`: Updated evaluation environment
- `logp`: Log joint density
"""
function evaluate!!(model::BUGSModel; temperature=1.0, transformed=model.transformed)
    evaluation_env, log_densities = evaluate_with_env!!(
        model; temperature=temperature, transformed=transformed
    )
    return evaluation_env, log_densities.tempered_logjoint
end

"""
    AbstractPPL.evaluate!!(model::BUGSModel, flattened_values::AbstractVector; temperature=1.0, transformed=model.transformed)

Evaluate model with the given parameter values.

# Arguments
- `model`: The BUGSModel to evaluate
- `flattened_values`: Vector of parameter values (in transformed or untransformed space)
- `temperature`: Temperature for tempering the likelihood (default 1.0)
- `transformed`: Whether the input values are in transformed space (default model.transformed)

# Returns
- `evaluation_env`: Updated evaluation environment
- `logp`: Log joint density
"""
function evaluate!!(
    model::BUGSModel,
    flattened_values::AbstractVector;
    temperature=1.0,
    transformed=model.transformed,
)
    if model.evaluation_mode isa UseAutoMarginalization
        evaluation_env, log_densities = evaluate_with_marginalization_values!!(
            model, flattened_values; temperature=temperature
        )
    else
        evaluation_env, log_densities = evaluate_with_values!!(
            model, flattened_values; temperature=temperature, transformed=transformed
        )
    end
    return evaluation_env, log_densities.tempered_logjoint
end
