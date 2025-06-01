# Accumulator for log densities
"""
    LogDensityAccumulator{T}

Mutable struct to accumulate log densities during model evaluation.

# Fields
- `logprior::T`: Log density of prior distributions
- `loglikelihood::T`: Log density of likelihood (observed variables)
"""
mutable struct LogDensityAccumulator{T}
    logprior::T
    loglikelihood::T
end

LogDensityAccumulator() = LogDensityAccumulator(0.0, 0.0)
LogDensityAccumulator{T}() where {T} = LogDensityAccumulator(zero(T), zero(T))

function tempered_logjoint(acc::LogDensityAccumulator; temperature=1.0)
    return acc.logprior + temperature * acc.loglikelihood
end

# Abstract evaluator type
"""
    AbstractEvaluator

Abstract type for different evaluation strategies.
Each evaluator implements a specific evaluation behavior while sharing a common interface.
"""
abstract type AbstractEvaluator end

# Evaluation modes
"""
    TransformationMode

Enum-like type to specify whether to use transformed or untransformed parameter space.
"""
abstract type TransformationMode end
struct Transformed <: TransformationMode end
struct Untransformed <: TransformationMode end

# Base evaluator with common fields
"""
    BaseEvaluator{TM<:TransformationMode}

Base type containing common fields for evaluators.
"""
abstract type BaseEvaluator{TM<:TransformationMode} <: AbstractEvaluator end

transformation_mode(::BaseEvaluator{TM}) where {TM} = TM()
get_pointwise_dict(e::BaseEvaluator) = e.pointwise_logdensities

# Concrete evaluator types
"""
    PriorSampler{TM}

Evaluator that samples from the prior distribution.
"""
struct PriorSampler{TM<:TransformationMode} <: BaseEvaluator{TM}
    rng::Random.AbstractRNG
    sample_all::Bool  # whether to sample conditioned variables as well
    pointwise_logdensities::Union{Nothing,Dict{VarName,Float64}}
end

function PriorSampler(
    rng=Random.default_rng(); sample_all=true, transformed=false, track_pointwise=false
)
    tm = transformed ? Transformed() : Untransformed()
    pw = track_pointwise ? Dict{VarName,Float64}() : nothing
    return PriorSampler{typeof(tm)}(rng, sample_all, pw)
end

"""
    VectorParameterEvaluator{TM}

Evaluator that uses a vector of parameter values.
"""
struct VectorParameterEvaluator{TM<:TransformationMode} <: BaseEvaluator{TM}
    values::AbstractVector
    pointwise_logdensities::Union{Nothing,Dict{VarName,Float64}}
end

function VectorParameterEvaluator(values; transformed=false, track_pointwise=false)
    tm = transformed ? Transformed() : Untransformed()
    pw = track_pointwise ? Dict{VarName,Float64}() : nothing
    return VectorParameterEvaluator{typeof(tm)}(values, pw)
end

"""
    EnvironmentEvaluator{TM}

Evaluator that uses values from the evaluation environment.
"""
struct EnvironmentEvaluator{TM<:TransformationMode} <: BaseEvaluator{TM}
    pointwise_logdensities::Union{Nothing,Dict{VarName,Float64}}
end

function EnvironmentEvaluator(; transformed=false, track_pointwise=false)
    tm = transformed ? Transformed() : Untransformed()
    pw = track_pointwise ? Dict{VarName,Float64}() : nothing
    return EnvironmentEvaluator{typeof(tm)}(pw)
end

# Helper to unwrap AD values
_unwrap_ad_value(x) = x
_unwrap_ad_value(x::Real) = convert(Float64, x)

# Helper to record pointwise log density
function record_pointwise!(evaluator::AbstractEvaluator, vn::VarName, logp)
    pw_dict = get_pointwise_dict(evaluator)
    if pw_dict !== nothing
        # Use the value function for AD compatibility
        pw_dict[vn] = _unwrap_ad_value(logp)
    end
end

# Main evaluation function
"""
    evaluate!!(evaluator::AbstractEvaluator, model::BUGSModel; kwargs...)

Evaluate the model using the specified evaluator strategy.

Returns:
- `evaluation_env`: Updated evaluation environment
- `logdensities`: NamedTuple with log densities (and optionally pointwise densities)
"""
function AbstractPPL.evaluate!!(
    evaluator::AbstractEvaluator, model::BUGSModel; temperature=1.0
)
    evaluation_env = deepcopy(model.evaluation_env)
    # Initialize accumulator with appropriate type for AD
    T = if evaluator isa VectorParameterEvaluator && length(evaluator.values) > 0
        eltype(evaluator.values)
    else
        Float64
    end
    acc = LogDensityAccumulator{T}()

    # Get variable lengths for VectorParameterEvaluator
    var_lengths = if evaluator isa VectorParameterEvaluator
        if transformation_mode(evaluator) isa Transformed
            model.transformed_var_lengths
        else
            model.untransformed_var_lengths
        end
    else
        nothing
    end

    current_idx = 1

    for (i, vn) in enumerate(model.graph_evaluation_data.sorted_nodes)
        is_stochastic = model.graph_evaluation_data.is_stochastic_vals[i]
        is_observed = model.graph_evaluation_data.is_observed_vals[i]
        node_function = model.graph_evaluation_data.node_function_vals[i]
        loop_vars = model.graph_evaluation_data.loop_vars_vals[i]

        if !is_stochastic
            # Deterministic node
            value = node_function(evaluation_env, loop_vars)
            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        else
            # Stochastic node
            dist = node_function(evaluation_env, loop_vars)

            # Get value based on evaluator type
            value, logp = get_value_and_logdensity(
                evaluator, dist, vn, evaluation_env, var_lengths, current_idx, is_observed
            )

            # Update current_idx for VectorParameterEvaluator
            if evaluator isa VectorParameterEvaluator && !is_observed
                current_idx += var_lengths[vn]
            end

            # Accumulate log density
            if is_observed
                acc.loglikelihood += logp
                record_pointwise!(evaluator, vn, logp)
            else
                acc.logprior += logp
                record_pointwise!(evaluator, vn, logp)
            end

            evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
        end
    end

    # Build result
    result = (
        logprior=acc.logprior,
        loglikelihood=acc.loglikelihood,
        tempered_logjoint=tempered_logjoint(acc; temperature),
    )

    pw_dict = get_pointwise_dict(evaluator)
    if pw_dict !== nothing
        result = merge(result, (pointwise_logdensities=pw_dict,))
    end

    return evaluation_env, result
end

# Dispatch for getting value and log density based on evaluator type
function get_value_and_logdensity(
    evaluator::PriorSampler, dist, vn, evaluation_env, var_lengths, current_idx, is_observed
)
    tm = transformation_mode(evaluator)
    if evaluator.sample_all || !is_observed
        # Sample from prior
        value = rand(evaluator.rng, dist)
        logp = compute_logdensity(typeof(tm), dist, value)
    else
        # Use observed value
        value = AbstractPPL.get(evaluation_env, vn)
        logp = compute_logdensity(typeof(tm), dist, value)
    end
    return value, logp
end

function get_value_and_logdensity(
    evaluator::VectorParameterEvaluator,
    dist,
    vn,
    evaluation_env,
    var_lengths,
    current_idx,
    is_observed,
)
    if is_observed
        # Use observed value from environment
        value = AbstractPPL.get(evaluation_env, vn)
        logp = logpdf(dist, value)
    else
        # Get value from vector
        l = var_lengths[vn]
        param_slice = view(evaluator.values, current_idx:(current_idx + l - 1))
        value, logp = extract_value_and_logdensity(
            typeof(transformation_mode(evaluator)), dist, param_slice
        )
    end
    return value, logp
end

function get_value_and_logdensity(
    evaluator::EnvironmentEvaluator,
    dist,
    vn,
    evaluation_env,
    var_lengths,
    current_idx,
    is_observed,
)
    value = AbstractPPL.get(evaluation_env, vn)
    logp = compute_logdensity(typeof(transformation_mode(evaluator)), dist, value)
    return value, logp
end

# Helper functions for computing log densities
function compute_logdensity(::Type{Untransformed}, dist, value)
    return logpdf(dist, value)
end

function compute_logdensity(::Type{Transformed}, dist, value)
    # Value is in original space, compute density with transformation adjustment
    value_transformed = Bijectors.transform(Bijectors.bijector(dist), value)
    return logpdf(dist, value) + Bijectors.logabsdetjac(
        Bijectors.inverse(Bijectors.bijector(dist)), value_transformed
    )
end

function extract_value_and_logdensity(::Type{Untransformed}, dist, param_slice)
    value = reconstruct(dist, param_slice)
    logp = logpdf(dist, value)
    return value, logp
end

function extract_value_and_logdensity(::Type{Transformed}, dist, param_slice)
    b = Bijectors.bijector(dist)
    b_inv = Bijectors.inverse(b)
    reconstructed_value = reconstruct(b_inv, dist, param_slice)
    value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)
    logp = logpdf(dist, value) + logjac
    return value, logp
end

# Compatibility functions for existing API
function AbstractPPL.evaluate!!(rng::Random.AbstractRNG, model::BUGSModel; sample_all=true)
    evaluator = PriorSampler(rng; sample_all, transformed=model.transformed)
    env, logdensities = evaluate!!(evaluator, model)
    return env, logdensities.tempered_logjoint
end

function AbstractPPL.evaluate!!(model::BUGSModel)
    evaluator = EnvironmentEvaluator(; transformed=model.transformed)
    env, logdensities = evaluate!!(evaluator, model)
    return env, logdensities.tempered_logjoint
end

function AbstractPPL.evaluate!!(model::BUGSModel, flattened_values::AbstractVector)
    evaluator = VectorParameterEvaluator(flattened_values; transformed=model.transformed)
    env, logdensities = evaluate!!(evaluator, model; temperature=1.0)
    return env, logdensities.tempered_logjoint
end

# Tempered evaluation function for backward compatibility
function _tempered_evaluate!!(
    model::BUGSModel, flattened_values::AbstractVector; temperature=1.0
)
    evaluator = VectorParameterEvaluator(flattened_values; transformed=model.transformed)
    return evaluate!!(evaluator, model; temperature)
end
