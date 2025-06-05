# AbstractBUGSModel cannot subtype `AbstractPPL.AbstractProbabilisticProgram` (which subtypes `AbstractMCMC.AbstractModel`)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    GraphEvaluationData{TNF,TV}

Caches node information from the model graph to optimize evaluation performance.
Stores pre-computed values to avoid repeated lookups from the MetaGraph during model evaluation.

# Fields
- `sorted_nodes::Vector{<:VarName}`: Variables in topological order for evaluation
- `sorted_parameters::Vector{<:VarName}`: Parameters (unobserved stochastic variables) in sorted order consistent with sorted_nodes
- `is_stochastic_vals::Vector{Bool}`: Whether each node represents a stochastic variable  
- `is_observed_vals::Vector{Bool}`: Whether each node is observed (has data)
- `node_function_vals::TNF`: Functions that define each node's computation
- `loop_vars_vals::TV`: Loop variables associated with each node
"""
struct GraphEvaluationData{TNF,TV}
    sorted_nodes::Vector{<:VarName}
    sorted_parameters::Vector{<:VarName}
    is_stochastic_vals::Vector{Bool}
    is_observed_vals::Vector{Bool}
    node_function_vals::TNF
    loop_vars_vals::TV
end

function GraphEvaluationData(
    g::BUGSGraph,
    sorted_nodes::Vector{<:VarName}=VarName[
        label_for(g, node) for node in topological_sort(g)
    ],
    active_parameters::Union{Nothing,Vector{<:VarName}}=nothing,
)
    is_stochastic_vals = Array{Bool}(undef, length(sorted_nodes))
    is_observed_vals = Array{Bool}(undef, length(sorted_nodes))
    node_function_vals = Array{Any}(undef, length(sorted_nodes))
    loop_vars_vals = Array{Any}(undef, length(sorted_nodes))
    sorted_parameters = VarName[]

    for (i, vn) in enumerate(sorted_nodes)
        (; is_stochastic, is_observed, node_function, loop_vars) = g[vn]
        is_stochastic_vals[i] = is_stochastic
        is_observed_vals[i] = is_observed
        node_function_vals[i] = node_function
        loop_vars_vals[i] = loop_vars

        # If it's a stochastic variable and not observed, it's a parameter
        # If active_parameters is specified, only include those that are in the list
        if is_stochastic && !is_observed
            if active_parameters === nothing || vn in active_parameters
                push!(sorted_parameters, vn)
            end
        end
    end

    return GraphEvaluationData(
        sorted_nodes,
        sorted_parameters,
        is_stochastic_vals,
        is_observed_vals,
        map(identity, node_function_vals),
        map(identity, loop_vars_vals),
    )
end

abstract type EvaluationMode end

struct UseGeneratedLogDensityFunction <: EvaluationMode end
struct UseGraph <: EvaluationMode end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

# Fields

- `model_def::Expr`: The original model definition (for serialization).
- `data::data_T`: The data associated with the model (for serialization).
- `g::BUGSGraph`: An instance of `BUGSGraph`, representing the dependency graph of the model.
- `evaluation_env::T`: A `NamedTuple` containing the values of the variables in the model, all the values are in the constrained space.
- `transformed::Bool`: Indicates whether the model parameters are in the transformed space.
- `evaluation_mode::EMT`: The mode for evaluating the log-density (either `UseGeneratedLogDensityFunction` or `UseGraph`).
- `untransformed_param_length::Int`: The length of the parameters vector in the original (constrained) space.
- `transformed_param_length::Int`: The length of the parameters vector in the transformed (unconstrained) space.
- `untransformed_var_lengths::Dict{<:VarName,Int}`: A dictionary mapping the names of the variables to their lengths in the original (constrained) space.
- `transformed_var_lengths::Dict{<:VarName,Int}`: A dictionary mapping the names of the variables to their lengths in the transformed (unconstrained) space.
- `graph_evaluation_data::GraphEvaluationData{TNF,TV}`: A `GraphEvaluationData` object containing pre-computed values of the nodes in the model, with sorted_parameters as the second field for easy access.
- `log_density_computation_function::F`: The generated function for computing log-density (if available).
- `base_model::base_model_T`: If not `Nothing`, the model is a conditioned model; otherwise, it's the model returned by `compile`.
"""
struct BUGSModel{
    EMT<:EvaluationMode,
    base_model_T<:Union{<:AbstractBUGSModel,Nothing},
    T<:NamedTuple,
    TNF,
    TV,
    data_T,
    F<:Union{Function,Nothing},
} <: AbstractBUGSModel
    model_def::Expr
    data::data_T

    g::BUGSGraph

    evaluation_env::T

    transformed::Bool
    evaluation_mode::EMT

    untransformed_param_length::Int
    transformed_param_length::Int
    untransformed_var_lengths::Dict{<:VarName,Int}
    transformed_var_lengths::Dict{<:VarName,Int}

    graph_evaluation_data::GraphEvaluationData{TNF,TV}

    log_density_computation_function::F

    base_model::base_model_T
end

# Constructor that takes a BUGSModel and keyword arguments, inheriting unspecified fields
function BUGSModel(
    model::BUGSModel;
    transformed::Bool=model.transformed,
    untransformed_param_length::Int=model.untransformed_param_length,
    transformed_param_length::Int=model.transformed_param_length,
    untransformed_var_lengths::Dict{<:VarName,Int}=model.untransformed_var_lengths,
    transformed_var_lengths::Dict{<:VarName,Int}=model.transformed_var_lengths,
    evaluation_env::NamedTuple=model.evaluation_env,
    graph_evaluation_data::GraphEvaluationData=model.graph_evaluation_data,
    g::BUGSGraph=model.g,
    base_model::Union{<:AbstractBUGSModel,Nothing}=model.base_model,
    evaluation_mode::EvaluationMode=model.evaluation_mode,
    log_density_computation_function::Union{Function,Nothing}=nothing,
    model_def::Expr=model.model_def,
    data=model.data,
)
    return BUGSModel(
        model_def,
        data,
        g,
        evaluation_env,
        transformed,
        evaluation_mode,
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        graph_evaluation_data,
        log_density_computation_function,
        base_model,
    )
end

function Base.show(io::IO, model::BUGSModel)
    # Print model type and dimension
    space_type =
        model.transformed ? "transformed (unconstrained)" : "original (constrained)"
    dim = if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end
    printstyled(io, "BUGSModel"; bold=true, color=:blue)
    println(io, " (parameters are in ", space_type, " space, with dimension ", dim, "):\n")

    # Group and print parameters
    printstyled(io, "  Model parameters:\n"; bold=true, color=:yellow)
    grouped_params = Dict{Symbol,Vector{VarName}}()
    for param in parameters(model)
        sym = AbstractPPL.getsym(param)
        push!(get!(grouped_params, sym, VarName[]), param)
    end
    for (sym, params) in grouped_params
        param_str = length(params) == 1 ? string(params[1]) : "$(join(params, ", "))"
        print(io, "    ")
        printstyled(io, param_str; color=:cyan)
        println(io)
    end
    println(io)

    # Print variable info
    printstyled(io, "  Variable sizes and types:\n"; bold=true, color=:yellow)
    for (name, value) in pairs(model.evaluation_env)
        type_str = if isa(value, Number)
            "type = $(typeof(value))"
        else
            "size = $(size(value)), type = $(typeof(value))"
        end
        print(io, "    ")
        printstyled(io, name; color=:cyan)
        print(io, ": ")
        printstyled(io, type_str; color=:green)
        println(io)
    end
    return nothing
end

function BUGSModel(
    g::BUGSGraph,
    evaluation_env::NamedTuple,
    model_def::Expr,
    data::NamedTuple,
    initial_params::NamedTuple=NamedTuple(),
    is_transformed::Bool=true,
)
    graph_evaluation_data = GraphEvaluationData(g)
    untransformed_param_length, transformed_param_length = 0, 0
    untransformed_var_lengths, transformed_var_lengths = Dict{VarName,Int}(),
    Dict{VarName,Int}()

    for (i, vn) in enumerate(graph_evaluation_data.sorted_nodes)
        is_stochastic = graph_evaluation_data.is_stochastic_vals[i]
        is_observed = graph_evaluation_data.is_observed_vals[i]
        node_function = graph_evaluation_data.node_function_vals[i]
        loop_vars = graph_evaluation_data.loop_vars_vals[i]

        if !is_stochastic
            value = Base.invokelatest(node_function, evaluation_env, loop_vars)
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        elseif !is_observed
            dist = Base.invokelatest(node_function, evaluation_env, loop_vars)

            untransformed_var_lengths[vn] = length(dist)
            # not all distributions are defined for `Bijectors.transformed`
            transformed_var_lengths[vn] = if Bijectors.bijector(dist) == identity
                untransformed_var_lengths[vn]
            else
                length(Bijectors.transformed(dist))
            end
            untransformed_param_length += untransformed_var_lengths[vn]
            transformed_param_length += transformed_var_lengths[vn]

            if haskey(initial_params, AbstractPPL.getsym(vn))
                initialization = AbstractPPL.get(initial_params, vn)
                evaluation_env = BangBang.setindex!!(evaluation_env, initialization, vn)
            else
                init_value = rand(dist)
                evaluation_env = BangBang.setindex!!(evaluation_env, init_value, vn)
            end
        end
    end

    lowered_model_def, reconstructed_model_def = JuliaBUGS._generate_lowered_model_def(
        model_def, g, evaluation_env
    )
    # if can't generate source, `_generate_lowered_model_def` will return a tuple of `nothing`
    has_generated_log_density_function = !isnothing(lowered_model_def)

    if has_generated_log_density_function
        log_density_computation_expr = JuliaBUGS._gen_log_density_computation_function_expr(
            lowered_model_def, evaluation_env, gensym(:__compute_log_density__)
        )
        log_density_computation_function = eval(log_density_computation_expr)
        pass = JuliaBUGS.CollectSortedNodes(evaluation_env)
        JuliaBUGS.analyze_block(pass, reconstructed_model_def)

        # Because CollectSortedNodes only looks at the LHS,
        # pass.sorted_nodes can contain variables that are not in the graph.
        # This is most likely caused by arrays that are only partially transformed data.
        sorted_nodes = filter(pass.sorted_nodes) do node
            node in graph_evaluation_data.sorted_nodes
        end

        graph_evaluation_data = GraphEvaluationData(g, sorted_nodes)
    else
        log_density_computation_function = nothing
    end

    return BUGSModel(
        model_def,
        data,
        g,
        evaluation_env,
        is_transformed,
        UseGraph(),
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        graph_evaluation_data,
        log_density_computation_function,
        nothing,
    )
end

## Model interface 

"""
    parameters(model::BUGSModel)

Return a vector of `VarName` containing the names of the model parameters (unobserved stochastic variables).
"""
parameters(model::BUGSModel) = model.graph_evaluation_data.sorted_parameters

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
    for (i, vn) in enumerate(model.graph_evaluation_data.sorted_nodes)
        is_stochastic = model.graph_evaluation_data.is_stochastic_vals[i]
        is_observed = model.graph_evaluation_data.is_observed_vals[i]
        node_function = model.graph_evaluation_data.node_function_vals[i]
        loop_vars = model.graph_evaluation_data.loop_vars_vals[i]
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
    for v in model.graph_evaluation_data.sorted_parameters
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
    for v in model.graph_evaluation_data.sorted_parameters
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
    # Check if switching to untransformed mode while using generated log density function
    if !bool && model.evaluation_mode isa UseGeneratedLogDensityFunction
        error(
            "Cannot set model to untransformed mode when using `UseGeneratedLogDensityFunction`. " *
            "The generated log density function only supports transformed (unconstrained) parameters. " *
            "Please use `set_evaluation_mode(model, UseGraph())` before switching to untransformed mode.",
        )
    end
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
    if model.log_density_computation_function === Nothing
        @warn(
            "The model does not support generated log density function, the evaluation mode is set to `UseGraph`."
        )
        mode = UseGraph()
    elseif !model.transformed && mode isa UseGeneratedLogDensityFunction
        error(
            "Cannot use `UseGeneratedLogDensityFunction` with untransformed model. " *
            "The generated log density function expects parameters in transformed (unconstrained) space. " *
            "Please use `settrans(model, true)` before switching to generated log density mode.",
        )
    end
    return BangBang.setproperty!!(model, :evaluation_mode, mode)
end
