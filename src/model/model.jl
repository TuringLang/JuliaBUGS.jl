# AbstractBUGSModel cannot subtype `AbstractPPL.AbstractProbabilisticProgram` (which subtypes `AbstractMCMC.AbstractModel`)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    FlattenedGraphNodeData{TNF,TNA,TV}

Pre-compute the values of the nodes in the model to avoid lookups from MetaGraph.
"""
struct FlattenedGraphNodeData{TNF,TV}
    sorted_nodes::Vector{<:VarName}
    is_stochastic_vals::Vector{Bool}
    is_observed_vals::Vector{Bool}
    node_function_vals::TNF
    loop_vars_vals::TV
end

function FlattenedGraphNodeData(
    g::BUGSGraph,
    sorted_nodes::Vector{<:VarName}=VarName[
        label_for(g, node) for node in topological_sort(g)
    ],
)
    is_stochastic_vals = Array{Bool}(undef, length(sorted_nodes))
    is_observed_vals = Array{Bool}(undef, length(sorted_nodes))
    node_function_vals = Array{Any}(undef, length(sorted_nodes))
    loop_vars_vals = Array{Any}(undef, length(sorted_nodes))
    for (i, vn) in enumerate(sorted_nodes)
        (; is_stochastic, is_observed, node_function, loop_vars) = g[vn]
        is_stochastic_vals[i] = is_stochastic
        is_observed_vals[i] = is_observed
        node_function_vals[i] = node_function
        loop_vars_vals[i] = loop_vars
    end
    return FlattenedGraphNodeData(
        sorted_nodes,
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
    BUGSModel{EMT, base_model_T, T, TNF, TV, data_T, F} <: AbstractBUGSModel

The `BUGSModel` is the central structure for representing a BUGS model after
compilation. It encapsulates all necessary information for inference, including
the model's graph structure, variable values, parameter definitions, and
evaluation strategy. This type implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl)
interface, allowing it to be used with various MCMC samplers.

The model can exist in two states regarding its parameters: original
(constrained) space or transformed (unconstrained) space, which is typically
required by HMC-like samplers.

# Type Parameters
- `EMT <: EvaluationMode`: Specifies the evaluation mode, e.g.,
  `UseGeneratedLogDensityFunction` for a statically compiled log-density
  function or `UseGraph` for graph-based evaluation.
- `base_model_T <: Union{<:AbstractBUGSModel,Nothing}`: The type of the base
  model. This is `Nothing` for a model directly from `compile`, or an
  `AbstractBUGSModel` instance if the current model is derived (e.g., by
  conditioning) from another.
- `T <: NamedTuple`: The type of the `evaluation_env`, which stores the current
  values of all variables in the model.
- `TNF`: The type of the `node_function_vals` field within the
  `FlattenedGraphNodeData`.
- `TV`: The type of the `loop_vars_vals` field within the
  `FlattenedGraphNodeData`.
- `data_T`: The type of the `data` field, which stores the original data
  provided to the model.
- `F <: Union{Function,Nothing}`: The type of the
  `log_density_computation_function`. This is a `Function` if a specialized
  log-density computation function was generated, and `Nothing` otherwise.

# Fields
- `transformed::Bool`: Indicates whether the model parameters are currently
  represented in the transformed (unconstrained) space (`true`) or the original
  (constrained) space (`false`).
- `untransformed_param_length::Int`: The total number of elements in the
  parameter vector when in the original (constrained) space.
- `transformed_param_length::Int`: The total number of elements in the parameter
  vector when in the transformed (unconstrained) space.
- `untransformed_var_lengths::Dict{<:VarName,Int}`: A dictionary mapping each
  parameter's `VarName` to its length in the original (constrained) space.
- `transformed_var_lengths::Dict{<:VarName,Int}`: A dictionary mapping each
  parameter's `VarName` to its length in the transformed (unconstrained) space.
- `evaluation_env::T`: A `NamedTuple` holding the current values of all
  variables (stochastic and deterministic) in the model. Values are stored in
  their original (constrained) space.
- `parameters::Vector{<:VarName}`: A vector of `VarName`s representing the model
  parameters (unobserved stochastic variables), ordered appropriately for
  constructing parameter vectors.
- `flattened_graph_node_data::FlattenedGraphNodeData{TNF,TV}`: Pre-computed
  data associated with the model's graph nodes, such as their stochasticity,
  observation status, and defining functions. This is optimized for quick
  lookups during model evaluation and is specific to a topological sort of the
  graph nodes.
- `g::BUGSGraph`: An instance of `BUGSGraph` representing the dependency
  structure of the model.
- `base_model::base_model_T`: If this model is the result of an operation like
  conditioning, `base_model` refers to the original model from which it was
  derived. Otherwise, it is `Nothing`.
- `evaluation_mode::EMT`: An instance of an `EvaluationMode` subtype,
  determining how the log-density is computed.
- `log_density_computation_function::F`: A pre-compiled function to compute the
  log-density of the model, if available (i.e., if `evaluation_mode` is
  `UseGeneratedLogDensityFunction`). Otherwise, `nothing`.
- `model_def::Expr`: The original Julia `Expr` defining the BUGS model, stored
  for serialization and introspection.
- `data::data_T`: The original data `NamedTuple` provided during model
  compilation, stored for serialization and potential re-evaluation.
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
    transformed::Bool
    untransformed_param_length::Int
    transformed_param_length::Int
    untransformed_var_lengths::Dict{<:VarName,Int}
    transformed_var_lengths::Dict{<:VarName,Int}
    evaluation_env::T
    parameters::Vector{<:VarName}
    flattened_graph_node_data::FlattenedGraphNodeData{TNF,TV}
    g::BUGSGraph
    base_model::base_model_T
    evaluation_mode::EMT
    log_density_computation_function::F
    model_def::Expr
    data::data_T
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
    for param in model.parameters
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
    flattened_graph_node_data = FlattenedGraphNodeData(g)
    parameters = VarName[]
    untransformed_param_length, transformed_param_length = 0, 0
    untransformed_var_lengths, transformed_var_lengths = Dict{VarName,Int}(),
    Dict{VarName,Int}()

    for (i, vn) in enumerate(flattened_graph_node_data.sorted_nodes)
        is_stochastic = flattened_graph_node_data.is_stochastic_vals[i]
        is_observed = flattened_graph_node_data.is_observed_vals[i]
        node_function = flattened_graph_node_data.node_function_vals[i]
        loop_vars = flattened_graph_node_data.loop_vars_vals[i]

        if !is_stochastic
            value = Base.invokelatest(node_function, evaluation_env, loop_vars)
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        elseif !is_observed
            push!(parameters, vn)
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

            initialization = try
                AbstractPPL.get(initial_params, vn)
            catch _
                missing
            end
            if !ismissing(initialization)
                evaluation_env = BangBang.setindex!!(evaluation_env, initialization, vn)
            else
                init_value = try
                    rand(dist)
                catch e
                    error(
                        "Failed to sample from the prior distribution of $vn, consider providing initialization values for $vn or it's parents: $(collect(MetaGraphsNext.inneighbor_labels(g, vn))...).",
                    )
                end
                evaluation_env = BangBang.setindex!!(evaluation_env, init_value, vn)
            end
        end
    end

    # TODO: stop using try-catch
    has_generated_log_density_function = false
    lowered_model_def = nothing
    reconstructed_model_def = nothing
    try
        lowered_model_def, reconstructed_model_def = _generate_lowered_model_def(
            model_def, g, evaluation_env
        )
        has_generated_log_density_function = true
    catch _
        has_generated_log_density_function = false
    end

    if has_generated_log_density_function
        log_density_computation_expr = _gen_log_density_computation_function_expr(
            lowered_model_def, evaluation_env, gensym(:__compute_log_density__)
        )
        log_density_computation_function = eval(log_density_computation_expr)
        pass = CollectSortedNodes(evaluation_env)
        JuliaBUGS.analyze_block(pass, reconstructed_model_def)
        sorted_nodes = pass.sorted_nodes
        original_parameters_length = length(parameters)
        parameters = VarName[vn for vn in sorted_nodes if vn in parameters]
        sorted_nodes = [
            vn for vn in sorted_nodes if vn in flattened_graph_node_data.sorted_nodes
        ]
        @assert length(parameters) == original_parameters_length "there are less parameters in the generated log density function than in the original model"
        flattened_graph_node_data = FlattenedGraphNodeData(g, sorted_nodes)
    else
        log_density_computation_function = nothing
    end

    # evaluation_mode =
    #     has_generated_log_density_function ? UseGeneratedLogDensityFunction() : UseGraph()

    return BUGSModel(
        is_transformed,
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        evaluation_env,
        parameters,
        flattened_graph_node_data,
        g,
        nothing,
        UseGraph(),
        log_density_computation_function,
        model_def,
        data,
    )
end

function BUGSModel(
    model::BUGSModel,
    g::BUGSGraph,
    parameters::Vector{<:VarName},
    sorted_nodes::Vector{<:VarName},
    evaluation_env::NamedTuple=model.evaluation_env,
)
    return BUGSModel(
        model.transformed,
        sum(model.untransformed_var_lengths[v] for v in parameters),
        sum(model.transformed_var_lengths[v] for v in parameters),
        model.untransformed_var_lengths,
        model.transformed_var_lengths,
        evaluation_env,
        parameters,
        FlattenedGraphNodeData(g, sorted_nodes),
        g,
        isnothing(model.base_model) ? model : model.base_model,
        model.evaluation_mode,
        model.log_density_computation_function,
        model.model_def,
        model.data,
    )
end
