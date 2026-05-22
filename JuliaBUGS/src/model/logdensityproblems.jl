using LogDensityProblems

function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    return Base.invokelatest(
        model.log_density_computation_function, model.evaluation_env, x
    )
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
- `adtype::AD`: AD backend (e.g., `AutoMooncake()`)
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
For Mooncake-backed AD, load `Mooncake` before constructing the wrapper. For
DifferentiationInterface-backed AD backends like `AutoReverseDiff()` and
`AutoForwardDiff()`, load `DifferentiationInterface` and the concrete backend
package before constructing the wrapper.

# AD Backend Compatibility

Different AD backends have different compatibility with evaluation modes:

- **`UseGeneratedLogDensityFunction`**: Only compatible with mutation-supporting backends
  like `AutoMooncake`, `AutoMooncakeForward`, and `AutoEnzyme`. The generated functions
  mutate arrays in-place.
- **`UseGraph`**: Compatible with `AutoMooncake`, `AutoReverseDiff`,
  `AutoForwardDiff`, and other backends that can handle the graph evaluator.
  `AutoMooncakeForward` is routed to `UseGeneratedLogDensityFunction`.
- **`UseAutoMarginalization`**: Compatible with graph-capable AD backends like
  `AutoMooncake`, `AutoReverseDiff`, and `AutoForwardDiff`. `AutoMooncakeForward`
  is not supported for this graph-based mode.

If an incompatible combination is detected, JuliaBUGS switches to a compatible
evaluation mode when possible.

# Example
```julia
model = compile(model_def, data)

using ADTypes, Mooncake
grad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```
"""
function BUGSModelWithGradient(model::BUGSModel, adtype::ADTypes.AbstractADType)
    # Check AD backend compatibility with evaluation mode
    model = _check_ad_compatibility(model, adtype)

    x = getparams(model)
    prep = _prepare_logdensity_gradient(adtype, model, x)
    return BUGSModelWithGradient(adtype, prep, model)
end

function _is_mooncake(adtype::ADTypes.AbstractADType)
    return adtype isa Union{ADTypes.AutoMooncake,ADTypes.AutoMooncakeForward}
end

function _is_mooncake_forward(adtype::ADTypes.AbstractADType)
    return adtype isa ADTypes.AutoMooncakeForward
end

# Whether the AD backend can differentiate through code that mutates arrays
# in-place, which is what `UseGeneratedLogDensityFunction` requires.
function _supports_mutation(adtype::ADTypes.AbstractADType)
    return _is_mooncake(adtype) || adtype isa ADTypes.AutoEnzyme
end

function _check_ad_compatibility(model::BUGSModel, adtype::ADTypes.AbstractADType)
    if model.evaluation_mode isa UseGeneratedLogDensityFunction &&
        !_supports_mutation(adtype)
        @warn "AD backend $(typeof(adtype)) does not support mutation required by " *
            "UseGeneratedLogDensityFunction mode. Switching to UseGraph mode." maxlog = 1
        return set_evaluation_mode(model, UseGraph())
    elseif model.evaluation_mode isa UseGraph && _is_mooncake_forward(adtype)
        model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
        if !(model.evaluation_mode isa UseGeneratedLogDensityFunction)
            throw(
                ArgumentError(
                    "AD backend $(typeof(adtype)) requires generated log-density mode, " *
                    "but JuliaBUGS could not generate a log-density function for this model.",
                ),
            )
        end
    elseif model.evaluation_mode isa UseAutoMarginalization && _is_mooncake_forward(adtype)
        throw(
            ArgumentError(
                "AD backend $(typeof(adtype)) does not support UseAutoMarginalization mode. " *
                "Use AutoMooncake/AutoForwardDiff/AutoReverseDiff for auto-marginalized " *
                "models, or switch to UseGeneratedLogDensityFunction mode if marginalization " *
                "is not required.",
            ),
        )
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
        # The generated log-density function is created by Core.eval when the
        # evaluation mode is selected. AbstractPPL.prepare probes the target
        # immediately, so prepare this target in the latest world age without
        # putting invokelatest inside the function differentiated by AD.
        return Base.invokelatest(
            AbstractPPL.prepare, adtype, _generated_logdensity_for_gradient(model), x
        )
    elseif adtype isa ADTypes.AutoMooncake
        # Mooncake's forward-mode path currently treats AbstractPPL context
        # arguments as AD inputs, but reverse mode can capture the model here so
        # only `x` is differentiated.
        return AbstractPPL.prepare(adtype, x -> _logdensity_for_gradient(x, model), x)
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
