using LogDensityProblems

function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    return model.log_density_computation_function(model.evaluation_env, x)
end

function _eval_logdensity(model, ::UseGraph, x)
    _, logp = AbstractPPL.evaluate!!(model, x)
    return logp
end

function _eval_logdensity(model, ::UseAutoMarginalization, x)
    _, log_densities = evaluate_with_marginalization_values!!(model, x)
    return log_densities.tempered_logjoint
end

function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    try
        return _eval_logdensity(model, model.evaluation_mode, x)
    catch e
        T = float(eltype(x))
        e isa DomainError && return T(-Inf)
        rethrow(e)
    end
end

function LogDensityProblems.dimension(model::BUGSModel)
    # For auto marginalization, only count continuous parameters
    if model.evaluation_mode isa UseAutoMarginalization
        mc = model.marginalization_cache
        continuous_param_length = 0
        for (i, vn) in enumerate(model.graph_evaluation_data.sorted_parameters)
            idx = findfirst(==(vn), model.graph_evaluation_data.sorted_nodes)
            if idx !== nothing
                node_type = mc.node_types[idx]
                # Only include continuous variables (exclude all discrete)
                if node_type == :continuous
                    if model.transformed
                        continuous_param_length += model.transformed_var_lengths[vn]
                    else
                        continuous_param_length += model.untransformed_var_lengths[vn]
                    end
                elseif node_type == :discrete_infinite
                    error(
                        "Model contains discrete infinite variable $(vn) which cannot be marginalized. " *
                        "Use UseGraph evaluation mode instead.",
                    )
                end
            end
        end
        return continuous_param_length
    else
        return if model.transformed
            model.transformed_param_length
        else
            model.untransformed_param_length
        end
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end

"""
    BUGSModelWithGradient{AD,P,M}

Wrap a `BUGSModel` with AD capabilities for gradient-based inference.

Implements `LogDensityProblems.logdensity` and `LogDensityProblems.logdensity_and_gradient`.

# Fields
- `adtype::AD`: AD backend (e.g., `AutoReverseDiff()`)
- `prep::P`: Prepared AD evaluator from AbstractPPL
- `base_model::M`: The underlying `BUGSModel`

See also [`compile`](@ref).
"""
struct BUGSModelWithGradient{AD<:ADTypes.AbstractADType,P,M<:BUGSModel}
    adtype::AD
    prep::P
    base_model::M
end

"""
    BUGSModelWithGradient(model::BUGSModel, adtype::ADTypes.AbstractADType)

Construct a gradient-enabled model wrapper from a BUGSModel and an AD backend.
For DifferentiationInterface-backed AD backends like `AutoReverseDiff()` and
`AutoForwardDiff()`, load `DifferentiationInterface` and the concrete backend
package before constructing the wrapper.

# AD Backend Compatibility

Different AD backends have different compatibility with evaluation modes:

- **`UseGeneratedLogDensityFunction`**: Only compatible with mutation-supporting backends
  like `AutoMooncake`, `AutoMooncakeForward`, and `AutoEnzyme`. The generated functions
  mutate arrays in-place.
- **`UseGraph`**: Compatible with `AutoReverseDiff`, `AutoForwardDiff`, and other
  tape-based or forward-mode backends that can handle the graph evaluator. Mooncake
  backends are routed to `UseGeneratedLogDensityFunction`.

If an incompatible combination is detected, JuliaBUGS switches to a compatible
evaluation mode when possible.

# Example
```julia
model = compile(model_def, data)
grad_model = BUGSModelWithGradient(model, AutoReverseDiff(compile=true))
```
"""
function BUGSModelWithGradient(model::BUGSModel, adtype::ADTypes.AbstractADType)
    # Check AD backend compatibility with evaluation mode
    model = _check_ad_compatibility(model, adtype)

    x = getparams(model)
    prep = Base.invokelatest(_prepare_logdensity_gradient, adtype, model, x)
    return BUGSModelWithGradient(adtype, prep, model)
end

# AD backends that support mutation (required for UseGeneratedLogDensityFunction)
function _supports_mutation(adtype::ADTypes.AbstractADType)
    return adtype isa
           Union{ADTypes.AutoMooncake,ADTypes.AutoMooncakeForward,ADTypes.AutoEnzyme}
end

function _check_ad_compatibility(model::BUGSModel, adtype::ADTypes.AbstractADType)
    if model.evaluation_mode isa UseGeneratedLogDensityFunction &&
        !_supports_mutation(adtype)
        @warn "AD backend $(typeof(adtype)) does not support mutation required by " *
            "UseGeneratedLogDensityFunction mode. Switching to UseGraph mode." maxlog = 1
        return set_evaluation_mode(model, UseGraph())
    elseif model.evaluation_mode isa UseGraph &&
        adtype isa Union{ADTypes.AutoMooncake,ADTypes.AutoMooncakeForward}
        model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
        if !(model.evaluation_mode isa UseGeneratedLogDensityFunction)
            throw(
                ArgumentError(
                    "AD backend $(typeof(adtype)) requires generated log-density mode, " *
                    "but JuliaBUGS could not generate a log-density function for this model.",
                ),
            )
        end
    end
    return model
end

# Forward base BUGSModel interface
function LogDensityProblems.logdensity(model::BUGSModelWithGradient, x::AbstractVector)
    return LogDensityProblems.logdensity(model.base_model, x)
end

function LogDensityProblems.dimension(model::BUGSModelWithGradient)
    return LogDensityProblems.dimension(model.base_model)
end

function LogDensityProblems.capabilities(::Type{<:BUGSModelWithGradient})
    return LogDensityProblems.LogDensityOrder{1}()  # Gradient available
end

"""
    _logdensity_for_gradient(x, model)

Target function for gradient computation via AbstractPPL's prepared AD evaluator API.
The parameter vector `x` comes first (the argument to differentiate w.r.t.),
and the model is passed as a constant context (not differentiated).
"""
function _logdensity_for_gradient(x::AbstractVector, model::BUGSModel)
    return _eval_logdensity(model, model.evaluation_mode, x)
end

function _generated_logdensity_for_gradient(model::BUGSModel)
    f = model.log_density_computation_function
    env = model.evaluation_env
    return x -> f(env, x)
end

function _prepare_logdensity_gradient(
    adtype::ADTypes.AbstractADType, model::BUGSModel, x::AbstractVector
)
    if model.evaluation_mode isa UseGeneratedLogDensityFunction
        return AbstractPPL.prepare(adtype, _generated_logdensity_for_gradient(model), x)
    end
    return AbstractPPL.prepare(adtype, _logdensity_for_gradient, x; context=(model,))
end

"""
    LogDensityProblems.logdensity_and_gradient(model::BUGSModelWithGradient, x)

Compute log density and its gradient using AbstractPPL's prepared AD evaluator API.
The gradient is copied out of the `value_and_gradient!!` cache before returning.
"""
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSModelWithGradient, x::AbstractVector
)
    try
        logp, grad = AbstractPPL.value_and_gradient!!(model.prep, x)
        return (logp, copy(grad))
    catch e
        if e isa DomainError
            T = float(eltype(x))
            return (T(-Inf), fill(T(NaN), length(x)))
        end
        rethrow(e)
    end
end
