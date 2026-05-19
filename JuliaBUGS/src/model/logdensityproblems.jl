using LogDensityProblems

function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    if !isempty(model.graph_evaluation_data.postprocess_stochastic)
        _, log_densities = evaluate_with_values!!(model, x; transformed=model.transformed)
        return log_densities.tempered_logjoint
    end
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
    param_vars = Model._active_parameter_vars(model)
    dim = 0
    if model.transformed
        for vn in param_vars
            dim += model.transformed_var_lengths[vn]
        end
    else
        for vn in param_vars
            dim += model.untransformed_var_lengths[vn]
        end
    end
    return dim
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
- `prep::P`: Prepared gradient from DifferentiationInterface
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

# AD Backend Compatibility

Different AD backends have different compatibility with evaluation modes:

- **`UseGeneratedLogDensityFunction`**: Only compatible with mutation-supporting backends
  like `AutoMooncake` and `AutoEnzyme`. The generated functions mutate arrays in-place.
- **`UseGraph`**: Compatible with `AutoReverseDiff`, `AutoForwardDiff`, and other
  tape-based or forward-mode backends. Also works with Mooncake and Enzyme.

If an incompatible combination is detected, a warning is issued and the model is
automatically switched to `UseGraph` mode.

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
    prep = DI.prepare_gradient(_logdensity_for_gradient, adtype, x, DI.Constant(model))
    return BUGSModelWithGradient(adtype, prep, model)
end

# AD backends that support mutation (required for UseGeneratedLogDensityFunction)
_supports_mutation(::ADTypes.AutoMooncake) = true
_supports_mutation(::ADTypes.AutoEnzyme) = true
_supports_mutation(::ADTypes.AbstractADType) = false

function _check_ad_compatibility(model::BUGSModel, adtype::ADTypes.AbstractADType)
    if model.evaluation_mode isa UseGeneratedLogDensityFunction &&
        !_supports_mutation(adtype)
        @warn "AD backend $(typeof(adtype)) does not support mutation required by " *
            "UseGeneratedLogDensityFunction mode. Switching to UseGraph mode." maxlog = 1
        return set_evaluation_mode(model, UseGraph())
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

Target function for gradient computation via DifferentiationInterface.
The parameter vector `x` comes first (the argument to differentiate w.r.t.),
and the model is passed as a constant context (not differentiated).
"""
function _logdensity_for_gradient(x::AbstractVector, model::BUGSModel)
    return _eval_logdensity(model, model.evaluation_mode, x)
end

"""
    LogDensityProblems.logdensity_and_gradient(model::BUGSModelWithGradient, x)

Compute log density and its gradient using DifferentiationInterface.
"""
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSModelWithGradient, x::AbstractVector
)
    try
        return DI.value_and_gradient(
            _logdensity_for_gradient,
            model.prep,
            model.adtype,
            x,
            DI.Constant(model.base_model),
        )
    catch e
        if e isa DomainError
            T = float(eltype(x))
            return (T(-Inf), fill(T(NaN), length(x)))
        end
        rethrow(e)
    end
end
