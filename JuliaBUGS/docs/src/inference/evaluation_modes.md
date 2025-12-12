# Evaluation Modes

JuliaBUGS supports multiple evaluation modes that determine how the log density is computed. The evaluation mode also constrains which AD backends can be used.

## Available Modes

| Mode | Description | AD Backends |
|------|-------------|-------------|
| `UseGraph()` | Traverses computational graph (default) | ReverseDiff, ForwardDiff |
| `UseGeneratedLogDensityFunction()` | Compiles a Julia function for log density | Mooncake |
| `UseAutoMarginalization()` | Graph traversal with discrete variable marginalization | ReverseDiff, ForwardDiff |

## UseGraph (Default)

The default mode evaluates the log density by traversing the computational graph. Works with ReverseDiff and ForwardDiff.

```julia
model = compile(model_def, data)
# UseGraph() is the default, no need to set explicitly
```

## UseGeneratedLogDensityFunction

This mode generates and compiles a Julia function for the log density, which can be faster for some models.

```julia
model = compile(model_def, data)
model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
```

Use with Mooncake for AD:

```julia
model = BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```

## UseAutoMarginalization

For models with discrete latent variables, auto-marginalization enables gradient-based inference by marginalizing out discrete parameters. See [Auto-Marginalization](auto_marginalization.md) for details.

```julia
model = compile(model_def, data)
model = settrans(model, true)  # requires transformed space
model = set_evaluation_mode(model, UseAutoMarginalization())
```

## API

```@docs
JuliaBUGS.Model.set_evaluation_mode
```
