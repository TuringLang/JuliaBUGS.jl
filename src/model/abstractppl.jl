import AbstractPPL: condition, decondition

"""
    condition(model::BUGSModel, conditioning_spec)

Create a new model by conditioning on specified variables with given values.

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
julia> using JuliaBUGS: @bugs, compile, @varname, initialize!

julia> using JuliaBUGS.Model: condition

julia> using Test

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

julia> model_cond.parameters
2-element Vector{AbstractPPL.VarName}:
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

julia> model_cond2.parameters  # All x[i] removed, only y remains
1-element Vector{AbstractPPL.VarName}:
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

julia> model_cond3.parameters  # y removed, only x[i] remain
3-element Vector{AbstractPPL.VarName}:
 x[3]
 x[2]
 x[1]

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

julia> model_cond4.parameters
2-element Vector{AbstractPPL.VarName}:
 x[2]
 y
```
"""
function condition(model::BUGSModel, conditioning_spec)
    var_values = _parse_conditioning_spec(conditioning_spec, model)::Dict{<:VarName,<:Any}
    vars_to_condition = collect(keys(var_values))::Vector{<:VarName}
    expanded_vars = _check_conditioning_validity(model, vars_to_condition)

    # If vars were expanded, we need to update var_values to include values for subsumed variables
    if length(expanded_vars) > length(vars_to_condition)
        expanded_var_values = Dict{VarName,Any}()
        for vn in expanded_vars
            if haskey(var_values, vn)
                expanded_var_values[vn] = var_values[vn]
            else
                # Find the original var that subsumes this one
                for (orig_vn, val) in var_values
                    if AbstractPPL.subsumes(orig_vn, vn)
                        # Extract the appropriate value for indexed variables
                        if val isa AbstractArray &&
                            AbstractPPL.getoptic(vn) isa Accessors.IndexLens
                            # Get the index from the variable name
                            idx = AbstractPPL.getoptic(vn).indices
                            expanded_var_values[vn] = val[idx...]
                        else
                            # For non-array values or non-indexed access, use the value directly
                            expanded_var_values[vn] = val
                        end
                        break
                    end
                end
            end
        end
        var_values = expanded_var_values
        vars_to_condition = expanded_vars
    end

    new_evaluation_env = _update_evaluation_env(model.evaluation_env, var_values)
    new_graph = _mark_as_observed(model.g, vars_to_condition)
    new_flattened_graph_node_data = FlattenedGraphNodeData(new_graph)
    new_parameters_unsorted = filter(vn -> vn ∉ vars_to_condition, model.parameters)
    new_parameters = VarName[
        vn for
        vn in new_flattened_graph_node_data.sorted_nodes if vn in new_parameters_unsorted
    ]
    new_untransformed_param_length = sum(
        model.untransformed_var_lengths[vn] for vn in new_parameters; init=0
    )
    new_transformed_param_length = sum(
        model.transformed_var_lengths[vn] for vn in new_parameters; init=0
    )
    return BUGSModel(
        model;
        untransformed_param_length=new_untransformed_param_length,
        transformed_param_length=new_transformed_param_length,
        evaluation_env=new_evaluation_env,
        parameters=new_parameters,
        flattened_graph_node_data=new_flattened_graph_node_data,
        g=new_graph,
        # Use flat design: base_model is either the original compiled model or nothing
        base_model=isnothing(model.base_model) ? model : model.base_model,
    )
end

# _parse_conditioning_spec should return Dict{::VarName, ::AllowedTypes}
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
        result[@varname($k)] = v
    end
    return result
end

function _mark_as_observed(g::BUGSGraph, vars::Vector{<:VarName})
    new_g = copy(g)
    for vn in vars
        node_info = new_g[vn]
        if node_info.is_stochastic && !node_info.is_observed
            new_g[vn] = BangBang.setproperty!!(node_info, :is_observed, true)
        end
    end
    return new_g
end

function _update_evaluation_env(env::NamedTuple, var_values::Dict{<:VarName,<:Any})
    new_env = env
    for (vn, value) in var_values
        new_env = BangBang.setindex!!(new_env, value, vn)
    end
    return new_env
end

function _check_conditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    expanded_vars = VarName[]

    for vn in vars
        if vn ∉ labels(model.g)
            # Check if there are any variables in the model that are subsumed by vn
            subsumed_vars = [
                label for label in labels(model.g) if AbstractPPL.subsumes(vn, label)
            ]

            if !isempty(subsumed_vars)
                # Warn user and expand to subsumed variables
                sorted_vars = sort(string.(subsumed_vars))
                @warn "Variable $vn does not exist in the model. Conditioning on subsumed variables instead: $(join(sorted_vars, ", "))"
                append!(expanded_vars, subsumed_vars)
            else
                throw(ArgumentError("Variable $vn does not exist in the model"))
            end
        else
            push!(expanded_vars, vn)
        end
    end

    # Check validity of all variables (original + expanded)
    for vn in expanded_vars
        node_info = model.g[vn]
        if !node_info.is_stochastic
            throw(
                ArgumentError(
                    "$vn is not a stochastic variable, conditioning on it is not supported"
                ),
            )
        end

        if node_info.is_observed
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
julia> using JuliaBUGS: @bugs, compile, @varname

julia> using JuliaBUGS.Model: condition, decondition

julia> using Test

julia> model_def = @bugs begin
           x ~ Normal(0, 1)
           y ~ Normal(x, 1) 
           z ~ Normal(y, 1)
       end;

julia> model = compile(model_def, (; z = 2.5));

julia> # Condition model
       model_cond = condition(model, (; x = 1.0, y = 1.5));

julia> model_cond.parameters
AbstractPPL.VarName[]

julia> # Partial deconditioning with specified variables
       model_d1 = decondition(model_cond, [@varname(y)]);

julia> model_d1.parameters
1-element Vector{AbstractPPL.VarName{:y, typeof(identity)}}:
 y

julia> # Full restoration to base model (no arguments)
       model_restored = decondition(model_cond);

julia> model_restored.parameters == model.parameters
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
ArgumentError("Model has no base_model. Use decondition(model, vars) to specify variables to decondition.")

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

julia> model_restored.parameters == model.parameters  # Back to original
true

julia> model_restored.evaluation_env.x  # But keeps the conditioned values
1.0

julia> model_restored.evaluation_env.y
2.0

julia> # m1 also restores to original model
       decondition(m1).parameters == model.parameters
true

julia> # Subsumption example
       model_arr = compile(@bugs(begin
           for i in 1:3
               v[i] ~ Normal(0, 1)
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

julia> model_arr_decon.parameters
3-element Vector{AbstractPPL.VarName{:v, Accessors.IndexLens{Tuple{Int64}}}}:
 v[3]
 v[2]
 v[1]
```
"""
function decondition(model::BUGSModel)
    if isnothing(model.base_model)
        throw(
            ArgumentError(
                "Model has no base_model. Use decondition(model, vars) to specify variables to decondition.",
            ),
        )
    end

    # Return base model with current evaluation environment
    return BUGSModel(model.base_model; evaluation_env=model.evaluation_env)
end

function decondition(model::BUGSModel, vars_to_decondition::Vector{<:VarName})
    # Expand variables if they subsume others (similar to condition)
    expanded_vars = _expand_vars_for_deconditioning(model, vars_to_decondition)

    # Check validity of variables to decondition
    _check_deconditioning_validity(model, expanded_vars)

    # Create new graph with variables unmarked as observed
    new_graph = _mark_as_unobserved(model.g, expanded_vars)

    # Recreate flattened graph node data
    new_flattened_graph_node_data = FlattenedGraphNodeData(new_graph)

    # Add deconditioned variables back to parameters
    # Need to maintain topological order
    new_parameters_unsorted = vcat(model.parameters, expanded_vars)
    new_parameters = [
        vn for
        vn in new_flattened_graph_node_data.sorted_nodes if vn in new_parameters_unsorted
    ]

    # Recalculate parameter lengths
    new_untransformed_param_length = sum(
        model.untransformed_var_lengths[vn] for vn in new_parameters; init=0
    )
    new_transformed_param_length = sum(
        model.transformed_var_lengths[vn] for vn in new_parameters; init=0
    )

    return BUGSModel(
        model;
        untransformed_param_length=new_untransformed_param_length,
        transformed_param_length=new_transformed_param_length,
        parameters=new_parameters,
        flattened_graph_node_data=new_flattened_graph_node_data,
        g=new_graph,
    )
end

# Expand variables for deconditioning (handle subsumption)
function _expand_vars_for_deconditioning(model::BUGSModel, vars::Vector{<:VarName})
    expanded_vars = VarName[]

    for vn in vars
        if vn ∉ labels(model.g)
            # Check if there are any observed variables that are subsumed by vn
            subsumed_observed = [
                label for label in labels(model.g) if AbstractPPL.subsumes(vn, label) &&
                model.g[label].is_observed &&
                model.g[label].is_stochastic
            ]

            if !isempty(subsumed_observed)
                # Warn user and expand to subsumed variables
                sorted_vars = sort(string.(subsumed_observed))
                @warn "Variable $vn does not exist in the model. Deconditioning subsumed observed variables instead: $(join(sorted_vars, ", "))"
                append!(expanded_vars, subsumed_observed)
            else
                # Will be caught in validity check
                push!(expanded_vars, vn)
            end
        else
            push!(expanded_vars, vn)
        end
    end

    return unique(expanded_vars)  # Remove duplicates
end

# Utility function to check validity of deconditioning
function _check_deconditioning_validity(model::BUGSModel, vars::Vector{<:VarName})
    # Get the original data variables (those observed at compile time)
    # These are the observed variables in the base model (or current model if no base)
    original_model = model
    while !isnothing(original_model.base_model)
        original_model = original_model.base_model
    end

    original_observed = Set{VarName}()
    for vn in labels(original_model.g)
        node_info = original_model.g[vn]
        if node_info.is_stochastic && node_info.is_observed
            push!(original_observed, vn)
        end
    end

    for vn in vars
        if vn ∉ labels(model.g)
            throw(ArgumentError("Variable $vn does not exist in the model"))
        end

        node_info = model.g[vn]

        if !node_info.is_stochastic
            throw(
                ArgumentError(
                    "$vn is not a stochastic variable, deconditioning is not supported"
                ),
            )
        end

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

# Utility function to mark variables as unobserved
function _mark_as_unobserved(g::BUGSGraph, vars::Vector{<:VarName})
    new_g = copy(g)
    for vn in vars
        node_info = new_g[vn]
        if node_info.is_stochastic && node_info.is_observed
            new_g[vn] = BangBang.setproperty!!(node_info, :is_observed, false)
        end
    end
    return new_g
end
