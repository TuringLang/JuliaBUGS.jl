# AbstractBUGSModel cannot subtype `AbstractPPL.AbstractProbabilisticProgram` (which subtypes `AbstractMCMC.AbstractModel`)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    is_discrete_finite_distribution(dist)

Check if a distribution is discrete with finite support.
"""
function is_discrete_finite_distribution(dist)
    # Check if it's a discrete distribution first
    if !(dist isa Distributions.DiscreteUnivariateDistribution)
        return false
    end

    # Whitelist of known finite discrete distributions
    return dist isa Union{
        Distributions.Bernoulli,
        Distributions.Binomial,
        Distributions.Categorical,
        Distributions.DiscreteUniform,
        Distributions.BetaBinomial,
        Distributions.Hypergeometric,
    }
end

"""
    enumerate_discrete_values(dist)

Return the finite support for a discrete univariate distribution.
Relies on Distributions.support to provide an iterable, finite range.
"""
enumerate_discrete_values(dist::Distributions.DiscreteUnivariateDistribution) = Distributions.support(
    dist
)

"""
    classify_node_type(dist)

Classify a distribution into node types for marginalization.
Returns one of: :deterministic, :discrete_finite, :discrete_infinite, :continuous
"""
function classify_node_type(dist)
    if is_discrete_finite_distribution(dist)
        return :discrete_finite
    elseif dist isa Distributions.DiscreteUnivariateDistribution
        return :discrete_infinite
    else
        return :continuous
    end
end

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
- `node_types::Vector{Symbol}`: Node type classification (:deterministic, :discrete_finite, :discrete_infinite, :continuous)
- `is_discrete_finite_vals::Vector{Bool}`: Whether each node is a discrete variable with finite support
"""
struct GraphEvaluationData{TNF,TV}
    sorted_nodes::Vector{<:VarName}
    sorted_parameters::Vector{<:VarName}
    is_stochastic_vals::Vector{Bool}
    is_observed_vals::Vector{Bool}
    node_function_vals::TNF
    loop_vars_vals::TV
    node_types::Vector{Symbol}
    is_discrete_finite_vals::Vector{Bool}
    minimal_cache_keys::Dict{Int,Vector{Int}}
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
    node_types = Array{Symbol}(undef, length(sorted_nodes))
    is_discrete_finite_vals = Array{Bool}(undef, length(sorted_nodes))
    sorted_parameters = VarName[]

    for (i, vn) in enumerate(sorted_nodes)
        (; is_stochastic, is_observed, node_function, loop_vars) = g[vn]
        is_stochastic_vals[i] = is_stochastic
        is_observed_vals[i] = is_observed
        node_function_vals[i] = node_function
        loop_vars_vals[i] = loop_vars

        # Default node types - will be updated during BUGSModel construction
        node_types[i] = :continuous
        is_discrete_finite_vals[i] = false

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
        node_types,
        is_discrete_finite_vals,
        Dict{Int,Vector{Int}}(),
    )
end

abstract type EvaluationMode end

struct UseGeneratedLogDensityFunction <: EvaluationMode end
struct UseGraph <: EvaluationMode end
struct UseAutoMarginalization <: EvaluationMode end

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
- `mutable_symbols::Set{Symbol}`: Set of symbols in the evaluation environment that may be mutated during evaluation (parameters and deterministic nodes).
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

    mutable_symbols::Set{Symbol}

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
    log_density_computation_function::Union{Function,Nothing}=model.log_density_computation_function,
    mutable_symbols::Set{Symbol}=model.mutable_symbols,
    model_def::Expr=model.model_def,
    data=model.data,
)
    # Build an intermediate model
    m = BUGSModel(
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
        mutable_symbols,
        base_model,
    )
    # Precompute minimal cache keys for current evaluation order if not present
    gd = m.graph_evaluation_data
    minimal_keys = if !isempty(gd.minimal_cache_keys)
        gd.minimal_cache_keys
    else
        n = length(gd.sorted_nodes)
        JuliaBUGS.Model._precompute_minimal_cache_keys(m, collect(1:n))
    end
    # Attach minimal order and keys to GraphEvaluationData
    order = if isempty(gd.marginalization_order)
        collect(1:length(gd.sorted_nodes))
    else
        gd.marginalization_order
    end
    gd2 = GraphEvaluationData(
        gd.sorted_nodes,
        gd.sorted_parameters,
        gd.is_stochastic_vals,
        gd.is_observed_vals,
        gd.node_function_vals,
        gd.loop_vars_vals,
        gd.node_types,
        gd.is_discrete_finite_vals,
        order,
        minimal_keys,
    )
    # Return final model with cached minimal keys
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
        gd2,
        log_density_computation_function,
        mutable_symbols,
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

    # Create mutable copies of node_types and is_discrete_finite_vals for updating
    node_types = copy(graph_evaluation_data.node_types)
    is_discrete_finite_vals = copy(graph_evaluation_data.is_discrete_finite_vals)

    for (i, vn) in enumerate(graph_evaluation_data.sorted_nodes)
        is_stochastic = graph_evaluation_data.is_stochastic_vals[i]
        is_observed = graph_evaluation_data.is_observed_vals[i]
        node_function = graph_evaluation_data.node_function_vals[i]
        loop_vars = graph_evaluation_data.loop_vars_vals[i]

        if !is_stochastic
            # Deterministic node
            node_types[i] = :deterministic
            is_discrete_finite_vals[i] = false
            value = Base.invokelatest(node_function, evaluation_env, loop_vars)
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        else
            # Stochastic node - evaluate distribution and classify
            dist = Base.invokelatest(node_function, evaluation_env, loop_vars)

            # Classify the node type based on the distribution
            node_types[i] = classify_node_type(dist)
            is_discrete_finite_vals[i] = (node_types[i] == :discrete_finite)

            if !is_observed
                # Unobserved stochastic node (parameter)
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
    end

    # Update graph_evaluation_data with the computed node types
    graph_evaluation_data = GraphEvaluationData(
        graph_evaluation_data.sorted_nodes,
        graph_evaluation_data.sorted_parameters,
        graph_evaluation_data.is_stochastic_vals,
        graph_evaluation_data.is_observed_vals,
        graph_evaluation_data.node_function_vals,
        graph_evaluation_data.loop_vars_vals,
        node_types,
        is_discrete_finite_vals,
        Dict{Int,Vector{Int}}(),
    )

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

        # Recreate GraphEvaluationData with the filtered sorted_nodes, but
        # preserve previously computed node classifications. The earlier
        # classification stored in `node_types` and `is_discrete_finite_vals`
        # corresponds to `graph_evaluation_data.sorted_nodes` before filtering.
        # A naive `GraphEvaluationData(g, sorted_nodes)` call would reset all
        # node types to defaults, losing this information.

        # Build a mapping from VarName -> classification from the original order
        old_nodes = graph_evaluation_data.sorted_nodes
        type_map = Dict{VarName,Symbol}(
            old_nodes[i] => node_types[i] for i in eachindex(old_nodes)
        )
        disc_map = Dict{VarName,Bool}(
            old_nodes[i] => is_discrete_finite_vals[i] for i in eachindex(old_nodes)
        )

        # Create a fresh GraphEvaluationData for the new order to reuse other fields
        new_gd = GraphEvaluationData(g, sorted_nodes)

        # Remap classification arrays to the new order
        new_node_types = Vector{Symbol}(undef, length(new_gd.sorted_nodes))
        new_is_discrete_finite_vals = Vector{Bool}(undef, length(new_gd.sorted_nodes))
        for (i, vn) in enumerate(new_gd.sorted_nodes)
            new_node_types[i] = get(type_map, vn, :continuous)
            new_is_discrete_finite_vals[i] = get(disc_map, vn, false)
        end

        # Reconstruct GraphEvaluationData while preserving classification
        graph_evaluation_data = GraphEvaluationData(
            new_gd.sorted_nodes,
            new_gd.sorted_parameters,
            new_gd.is_stochastic_vals,
            new_gd.is_observed_vals,
            new_gd.node_function_vals,
            new_gd.loop_vars_vals,
            new_node_types,
            new_is_discrete_finite_vals,
            Dict{Int,Vector{Int}}(),
        )
    else
        log_density_computation_function = nothing
    end

    # Compute mutable symbols from graph evaluation data
    mutable_symbols = get_mutable_symbols(graph_evaluation_data)

    # Build initial model (without minimal cache keys precomputed)
    model_without_min_keys = BUGSModel(
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
        mutable_symbols,
        nothing,
    )
    # Precompute minimal cache keys for the default order (1:n)
    n = length(graph_evaluation_data.sorted_nodes)
    sorted_indices = collect(1:n)
    minimal_keys = JuliaBUGS.Model._precompute_minimal_cache_keys(
        model_without_min_keys, sorted_indices
    )
    # Attach minimal keys to GraphEvaluationData
    graph_evaluation_data_with_keys = GraphEvaluationData(
        graph_evaluation_data.sorted_nodes,
        graph_evaluation_data.sorted_parameters,
        graph_evaluation_data.is_stochastic_vals,
        graph_evaluation_data.is_observed_vals,
        graph_evaluation_data.node_function_vals,
        graph_evaluation_data.loop_vars_vals,
        graph_evaluation_data.node_types,
        graph_evaluation_data.is_discrete_finite_vals,
        minimal_keys,
    )

    # Return final model with cached minimal keys
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
        graph_evaluation_data_with_keys,
        log_density_computation_function,
        mutable_symbols,
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
    getparams([T::Type], model::BUGSModel, evaluation_env=model.evaluation_env)

Extract parameter values from the model.

# Arguments
- `T::Type`: Optional output type. If not specified, returns a `Vector{Float64}`. 
  If `T <: AbstractDict`, returns a dictionary with `VarName` keys and parameter values.
- `model::BUGSModel`: The BUGS model from which to extract parameters.
- `evaluation_env`: The evaluation environment to use for extracting parameter values. 
  Defaults to `model.evaluation_env`.

# Returns
- If `T` is not specified: `Vector{Float64}` - A flattened vector containing all parameter 
  values in the order consistent with `LogDensityProblems.logdensity`.
- If `T <: AbstractDict`: A dictionary of type `T` with `VarName` keys and parameter values.

# Notes
- If `model.transformed` is true, returns parameters in the transformed (unconstrained) space.
- If `model.transformed` is false, returns parameters in their original (constrained) space.

# Examples
```julia
# Get parameters as a vector
params_vec = getparams(model)

# Get parameters as a dictionary
params_dict = getparams(Dict, model)

# Use a custom evaluation environment
params_vec = getparams(model, custom_env)
params_dict = getparams(Dict, model, custom_env)
```
"""
function getparams(model::BUGSModel, evaluation_env=model.evaluation_env)
    param_length = if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end

    param_vals = Vector{Float64}(undef, param_length)
    pos = 1
    for v in model.graph_evaluation_data.sorted_parameters
        if !model.transformed
            val = AbstractPPL.get(evaluation_env, v)
            len = model.untransformed_var_lengths[v]
            if val isa AbstractArray
                param_vals[pos:(pos + len - 1)] .= vec(val)
            else
                param_vals[pos] = val
            end
        else
            (; node_function, loop_vars) = model.g[v]
            dist = Base.invokelatest(node_function, evaluation_env, loop_vars)
            transformed_value = Bijectors.transform(
                Bijectors.bijector(dist), AbstractPPL.get(evaluation_env, v)
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

function getparams(
    T::Type{<:AbstractDict}, model::BUGSModel, evaluation_env=model.evaluation_env
)
    d = T()
    for v in model.graph_evaluation_data.sorted_parameters
        value = AbstractPPL.get(evaluation_env, v)
        if !model.transformed
            d[v] = value
        else
            (; node_function, loop_vars) = model.g[v]
            dist = Base.invokelatest(node_function, evaluation_env, loop_vars)
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
    if mode isa UseGeneratedLogDensityFunction
        if isnothing(model.log_density_computation_function)
            @warn(
                "The model does not support generated log density function, the evaluation mode is set to `UseGraph`."
            )
            mode = UseGraph()
        elseif !model.transformed
            error(
                "Cannot use `UseGeneratedLogDensityFunction` with untransformed model. " *
                "The generated log density function expects parameters in transformed (unconstrained) space. " *
                "Please use `settrans(model, true)` before switching to generated log density mode.",
            )
        end
    elseif mode isa UseAutoMarginalization
        if !model.transformed
            error(
                "Cannot use `UseAutoMarginalization` with untransformed model. " *
                "Auto marginalization expects parameters in transformed (unconstrained) space. " *
                "Please use `settrans(model, true)` before switching to auto marginalization mode.",
            )
        end
    end
    return BangBang.setproperty!!(model, :evaluation_mode, mode)
end
