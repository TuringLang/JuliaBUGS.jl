"""
    parameters(model::BUGSModel)

Return a vector of `VarName` containing the names of the model parameters (unobserved stochastic variables).
"""
parameters(model::BUGSModel) = model.parameters

"""
    variables(model::BUGSModel)

Return a vector of `VarName` containing the names of all the variables in the model.
"""
variables(model::BUGSModel) = collect(labels(model.g))

const AllowedArray{T} = AbstractArray{T} where {T<:Union{Int,Float64,Missing}}
const AllowedValue = Union{Int,Float64,Missing,AllowedArray}

"""
    initialize!(model::BUGSModel, initial_params::NamedTuple{<:Any, <:Tuple{Vararg{AllowedValue}}})

Initialize the model with a NamedTuple of initial values, the values are expected to be in the original space.
"""
function initialize!(
    model::BUGSModel, initial_params::NamedTuple{<:Any,<:Tuple{Vararg{AllowedValue}}}
)
    for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        node_function = model.flattened_graph_node_data.node_function_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]
        if !is_stochastic
            value = Base.invokelatest(node_function, model.evaluation_env, loop_vars)
            BangBang.@set!! model.evaluation_env = setindex!!(
                model.evaluation_env, value, vn
            )
        elseif !is_observed
            initialization = try
                AbstractPPL.get(initial_params, vn)
            catch _
                missing
            end
            if !ismissing(initialization)
                BangBang.@set!! model.evaluation_env = setindex!!(
                    model.evaluation_env, initialization, vn
                )
            else
                BangBang.@set!! model.evaluation_env = setindex!!(
                    model.evaluation_env,
                    rand(Base.invokelatest(node_function, model.evaluation_env, loop_vars)),
                    vn,
                )
            end
        end
    end
    return model
end

"""
    initialize!(model::BUGSModel, initial_params::AbstractVector)

Initialize the model with a vector of initial values, the values can be in transformed space if `model.transformed` is set to true.
"""
function initialize!(model::BUGSModel, initial_params::AbstractVector)
    evaluation_env, _ = AbstractPPL.evaluate!!(model, initial_params)
    return BangBang.setproperty!!(model, :evaluation_env, evaluation_env)
end

"""
    getparams(model::BUGSModel)

Extract the parameter values from the model as a flattened vector, in an order consistent with
the what `LogDensityProblems.logdensity` expects.
"""
function getparams(model::BUGSModel)
    param_length = if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end

    param_vals = Vector{Float64}(undef, param_length)
    pos = 1
    for v in model.parameters
        if !model.transformed
            val = AbstractPPL.get(model.evaluation_env, v)
            len = model.untransformed_var_lengths[v]
            if val isa AbstractArray
                param_vals[pos:(pos + len - 1)] .= vec(val)
            else
                param_vals[pos] = val
            end
        else
            (; node_function, loop_vars) = model.g[v]
            dist = node_function(model.evaluation_env, loop_vars)
            transformed_value = Bijectors.transform(
                Bijectors.bijector(dist), AbstractPPL.get(model.evaluation_env, v)
            )
            len = model.transformed_var_lengths[v]
            if transformed_value isa AbstractArray
                param_vals[pos:(pos + len - 1)] .= vec(transformed_value)
            else
                param_vals[pos] = transformed_value
            end
        end
        pos += len
    end
    return param_vals
end

"""
    getparams(T::Type{<:AbstractDict}, model::BUGSModel)

Extract the parameter values from the model into a dictionary of type T.
If model.transformed is true, returns parameters in transformed space.
"""
function getparams(T::Type{<:AbstractDict}, model::BUGSModel)
    d = T()
    for v in model.parameters
        value = AbstractPPL.get(model.evaluation_env, v)
        if !model.transformed
            d[v] = value
        else
            (; node_function, loop_vars) = model.g[v]
            dist = node_function(model.evaluation_env, loop_vars)
            d[v] = Bijectors.transform(Bijectors.bijector(dist), value)
        end
    end
    return d
end

"""
    settrans(model::BUGSModel, bool::Bool=!(model.transformed))

The `BUGSModel` contains information for evaluation in both transformed and untransformed spaces. The `transformed` field
indicates the current "mode" of the model.

This function enables switching the "mode" of the model.
"""
function settrans(model::BUGSModel, bool::Bool=(!(model.transformed)))
    return BangBang.setproperty!!(model, :transformed, bool)
end


"""
    set_evaluation_mode(model::BUGSModel, mode::EvaluationMode)

Set the evaluation mode for the `BUGSModel`.

The evaluation mode determines how the log-density of the model is computed.
Possible modes are:
- `UseGeneratedLogDensityFunction()`: Uses a statically generated function for log-density computation. This is often faster but may not be available for all models. If the model does not support a generated log-density function (i.e., `model.log_density_computation_function === identity`), a warning is issued, and the mode defaults to `UseGraph()`.
- `UseGraph()`: Computes the log-density by traversing the model's graph structure. This is always available but might be slower.

# Arguments
- `model::BUGSModel`: The BUGS model instance.
- `mode::EvaluationMode`: The desired evaluation mode.

# Returns
- A new `BUGSModel` instance with the `evaluation_mode` field updated. If the original model is mutable, it might be modified in place.

# Examples
```julia
# Assuming `model` is a compiled BUGSModel instance
model_with_graph_eval = set_evaluation_mode(model, UseGraph())
model_with_generated_eval = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
```
"""
function set_evaluation_mode(model::BUGSModel, mode::EvaluationMode)
    if model.log_density_computation_function === identity
        @warn(
            "The model does not support generated log density function, the evaluation mode is set to `UseGraph`."
        )
        mode = UseGraph()
    end
    return BangBang.setproperty!!(model, :evaluation_mode, mode)
end
