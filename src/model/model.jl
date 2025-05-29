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
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.
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
    " Indicates whether the model parameters are in the transformed space. "
    transformed::Bool

    "The length of the parameters vector in the original (constrained) space."
    untransformed_param_length::Int
    "The length of the parameters vector in the transformed (unconstrained) space."
    transformed_param_length::Int
    "A dictionary mapping the names of the variables to their lengths in the original (constrained) space."
    untransformed_var_lengths::Dict{<:VarName,Int}
    "A dictionary mapping the names of the variables to their lengths in the transformed (unconstrained) space."
    transformed_var_lengths::Dict{<:VarName,Int}

    "A `NamedTuple` containing the values of the variables in the model, all the values are in the constrained space."
    evaluation_env::T
    "A vector containing the names of the model parameters (unobserved stochastic variables)."
    parameters::Vector{<:VarName}
    "An `FlattenedGraphNodeData` object containing pre-computed values of the nodes in the model. For each topological order, this needs to be recomputed."
    flattened_graph_node_data::FlattenedGraphNodeData{TNF,TV}

    "An instance of `BUGSGraph`, representing the dependency graph of the model."
    g::BUGSGraph

    "If not `Nothing`, the model is a conditioned model; otherwise, it's the model returned by `compile`."
    base_model::base_model_T

    evaluation_mode::EMT
    log_density_computation_function::F

    # for serialization, save the original model definition and data
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

const AllowedArray{T} = AbstractArray{T} where {T<:Union{Int,Float64,Missing}}
const AllowedValue = Union{Int, Float64, Missing, AllowedArray}

"""
    initialize!(model::BUGSModel, initial_params::NamedTuple{<:Any, <:Tuple{Vararg{AllowedValue}}})

Initialize the model with a NamedTuple of initial values, the values are expected to be in the original space.
"""
function initialize!(model::BUGSModel, initial_params::NamedTuple{<:Any, <:Tuple{Vararg{AllowedValue}}})
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
function settrans(model::BUGSModel, bool::Bool=!(model.transformed))
    return BangBang.setproperty!!(model, :transformed, bool)
end

function set_evaluation_mode(model::BUGSModel, mode::EvaluationMode)
    if model.log_density_computation_function === identity
        @warn(
            "The model does not support generated log density function, the evaluation mode is set to `UseGraph`."
        )
        mode = UseGraph()
    end
    return BangBang.setproperty!!(model, :evaluation_mode, mode)
end
