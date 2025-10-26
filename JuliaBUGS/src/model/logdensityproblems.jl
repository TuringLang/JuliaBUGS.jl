using LogDensityProblems

function _eval_logdensity(model, ::UseGeneratedLogDensityFunction, x)
    return model.log_density_computation_function(model.evaluation_env, x)
end

function _eval_logdensity(model, ::UseGraph, x)
    _, logp = AbstractPPL.evaluate!!(model, x)
    return logp
end

function LogDensityProblems.logdensity(model::BUGSModel, x::AbstractArray)
    return _eval_logdensity(model, model.evaluation_mode, x)
end

function LogDensityProblems.dimension(model::BUGSModel)
    return if model.transformed
        model.transformed_param_length
    else
        model.untransformed_param_length
    end
end

function LogDensityProblems.capabilities(::AbstractBUGSModel)
    return LogDensityProblems.LogDensityOrder{0}()
end

"""
    BUGSModelWithGradient{B,P,M}

Wraps a BUGSModel with automatic differentiation capabilities using DifferentiationInterface.
Implements both `LogDensityProblems.logdensity` and `LogDensityProblems.logdensity_and_gradient`.

# Fields
- `backend::B`: ADTypes backend (e.g., AutoReverseDiff())
- `prep::P`: Prepared gradient from DifferentiationInterface (can be nothing)
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
struct BUGSModelWithGradient{B<:ADTypes.AbstractADType,P,M<:BUGSModel}
    backend::B
    prep::P
    base_model::M
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
    _logdensity_switched(x, base_model_constant)

Helper function that switches argument order for DifferentiationInterface compatibility.
DI expects the active argument (to differentiate w.r.t.) to come first.
"""
function _logdensity_switched(x::AbstractVector, base_model_constant::DI.Constant)
    base_model = DI.unwrap(base_model_constant)
    return LogDensityProblems.logdensity(base_model, x)
end

# Fallback for testing during preparation (when DI calls without Constant wrapper)
function _logdensity_switched(x::AbstractVector, base_model::BUGSModel)
    return LogDensityProblems.logdensity(base_model, x)
end

"""
    LogDensityProblems.logdensity_and_gradient(model::BUGSModelWithGradient, x)

Compute log density and its gradient using DifferentiationInterface.
Uses prepared gradient if available, otherwise falls back to unprepared computation.
"""
function LogDensityProblems.logdensity_and_gradient(
    model::BUGSModelWithGradient, x::AbstractVector
)
    # Active argument (x) comes first for DI
    # Base model passed as Constant context
    if model.prep === nothing
        return DI.value_and_gradient(
            _logdensity_switched, model.backend, x, DI.Constant(model.base_model)
        )
    else
        return DI.value_and_gradient(
            _logdensity_switched,
            model.prep,
            model.backend,
            x,
            DI.Constant(model.base_model),
        )
    end
end
