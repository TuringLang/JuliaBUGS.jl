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
    return _eval_logdensity(model, model.evaluation_mode, x)
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

Wraps a BUGSModel with automatic differentiation capabilities using DifferentiationInterface.
Implements both `LogDensityProblems.logdensity` and `LogDensityProblems.logdensity_and_gradient`.

# Fields
- `adtype::AD`: ADTypes backend (e.g., AutoReverseDiff())
- `prep::P`: Prepared gradient from DifferentiationInterface
- `base_model::M`: The underlying BUGSModel

# Example
```julia
model_def = @bugs begin
    x ~ dnorm(0, 1)
end
data = NamedTuple()

# Create model with gradient capabilities
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

# Use with gradient-based MCMC
chain = AbstractMCMC.sample(rng, model, NUTS(0.8), 1000)
```
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
    _logdensity_for_gradient(x, model_constant)

Target function for gradient computation via DifferentiationInterface.
The parameter vector `x` comes first (the argument to differentiate w.r.t.),
and the model is wrapped in `DI.Constant` to indicate it's not differentiated.
"""
function _logdensity_for_gradient(x::AbstractVector, model_constant::DI.Constant)
    model = DI.unwrap(model_constant)
    return _eval_logdensity(model, model.evaluation_mode, x)
end

"""
    LogDensityProblems.logdensity_and_gradient(model::BUGSModelWithGradient, x)

Compute log density and its gradient using DifferentiationInterface.
"""
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSModelWithGradient, x::AbstractVector
)
    return DI.value_and_gradient(
        _logdensity_for_gradient, model.prep, model.adtype, x, DI.Constant(model.base_model)
    )
end
