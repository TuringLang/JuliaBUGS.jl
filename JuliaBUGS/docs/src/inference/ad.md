# Automatic Differentiation

JuliaBUGS integrates with automatic differentiation (AD) through AbstractPPL's prepared AD evaluator interface, enabling gradient-based inference methods like Hamiltonian Monte Carlo (HMC) and No-U-Turn Sampler (NUTS). AbstractPPL provides two AD integration paths: a DifferentiationInterface extension that routes AD packages like ReverseDiff and ForwardDiff (selected via `AutoReverseDiff()`/`AutoForwardDiff()`) through DI's wrapper, and a native Mooncake extension that handles `AutoMooncake()` (reverse mode) and `AutoMooncakeForward()` (forward mode) directly. JuliaBUGS does not load these packages for you, so load `DifferentiationInterface` together with the concrete AD package for `AutoForwardDiff()`/`AutoReverseDiff()`, or load `Mooncake` for `AutoMooncake()`/`AutoMooncakeForward()`.

For distributed sampling, load the same packages on every worker before sending a gradient-enabled model to workers, for example `@everywhere using DifferentiationInterface, ReverseDiff` for `AutoReverseDiff()`, or `@everywhere using Mooncake` for `AutoMooncake()`.

## Specifying an AD Backend

To compile a model with gradient support, pass the `adtype` parameter to `compile`:

```julia
# Compile with gradient support using ADTypes from ADTypes.jl
using ADTypes, DifferentiationInterface, ReverseDiff
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))
```

Alternatively, if you already have a compiled `BUGSModel`, you can wrap it with `BUGSModelWithGradient` without recompiling:

```julia
base_model = compile(model_def, data)
model = BUGSModelWithGradient(base_model, AutoReverseDiff(compile=true))
```

## Available AD Backends

| Backend | When to use |
|---------|-------------|
| `AutoReverseDiff(compile=true)` | Recommended for most models |
| `AutoReverseDiff(compile=false)` | Models with control flow |
| `AutoForwardDiff()` | Small models (< 20 parameters) |
| `AutoMooncake()` | With `UseGeneratedLogDensityFunction()` mode |
| `AutoMooncakeForward()` | Forward-mode Mooncake with `UseGeneratedLogDensityFunction()` mode |

The compiled model with gradient support implements the [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/) interface, including [`logdensity_and_gradient`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity_and_gradient), which returns both the log density and its gradient.

For `UseAutoMarginalization()` mode, use `AutoReverseDiff()` or `AutoForwardDiff()`. Mooncake currently requires generated log-density mode and does not support auto-marginalized models.

## AD Backends with `UseGraph()` Mode

Use [ReverseDiff.jl](https://github.com/JuliaDiff/ReverseDiff.jl) or [ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl) with the default `UseGraph()` mode:

```julia
using ADTypes, DifferentiationInterface
using ForwardDiff, ReverseDiff

# ReverseDiff with tape compilation (recommended for large models)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

# ForwardDiff (efficient for small models with < 20 parameters)
model = compile(model_def, data; adtype=AutoForwardDiff())

# ReverseDiff without compilation (supports control flow)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=false))
```

!!! note "Control flow and compiled tapes"
    BUGS syntax is declarative and doesn't include control flow (`if`, `while`), so most models work fine with compiled tapes. However, if you register custom functions via `@bugs_primitive` that internally use control flow, the compiled tape will only capture one execution path. In such cases, use `AutoReverseDiff(compile=false)` or `AutoForwardDiff()` instead.

## AD Backend with `UseGeneratedLogDensityFunction()` Mode

Use [Mooncake.jl](https://github.com/compintell/Mooncake.jl) with the generated log density function mode:

```julia
using ADTypes, Mooncake

base_model = compile(model_def, data)
base_model = set_evaluation_mode(base_model, UseGeneratedLogDensityFunction())
model = BUGSModelWithGradient(base_model, AutoMooncake(; config=nothing))

# Forward-mode Mooncake is also available for small generated-function models.
forward_model = BUGSModelWithGradient(base_model, AutoMooncakeForward(; config=nothing))
```

For more details on evaluation modes, see [Evaluation Modes](evaluation_modes.md).
