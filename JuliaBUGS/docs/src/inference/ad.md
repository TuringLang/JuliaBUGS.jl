# Automatic Differentiation

JuliaBUGS integrates with automatic differentiation (AD) through [DifferentiationInterface.jl](https://github.com/JuliaDiff/DifferentiationInterface.jl), enabling gradient-based inference methods like Hamiltonian Monte Carlo (HMC) and No-U-Turn Sampler (NUTS).

## Specifying an AD Backend

To compile a model with gradient support, pass the `adtype` parameter to `compile`:

```julia
# Compile with gradient support using ADTypes from ADTypes.jl
using ADTypes
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

The compiled model with gradient support implements the [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/) interface, including [`logdensity_and_gradient`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity_and_gradient), which returns both the log density and its gradient.

## AD Backends with `UseGraph()` Mode

Use [ReverseDiff.jl](https://github.com/JuliaDiff/ReverseDiff.jl) or [ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl) with the default `UseGraph()` mode:

```julia
using ADTypes

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
using ADTypes

model = compile(model_def, data)
model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
model = BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```

For more details on evaluation modes, see [Evaluation Modes](evaluation_modes.md).
