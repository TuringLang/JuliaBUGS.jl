# Evaluation Modes

JuliaBUGS supports multiple evaluation modes that determine how the log density is computed. The evaluation mode also constrains which AD backends can be used.

## Available Modes

| Mode | Description | AD Backends |
|------|-------------|-------------|
| `UseGraph()` | Traverses computational graph (default) | AutoMooncake, ReverseDiff, ForwardDiff |
| `UseGeneratedLogDensityFunction()` | Compiles a Julia function for log density | AutoMooncake, AutoMooncakeForward |
| `UseAutoMarginalization()` | Graph traversal with discrete variable marginalization | AutoMooncake, ReverseDiff, ForwardDiff |

## UseGraph (Default)

The default mode evaluates the log density by traversing the computational graph. It works with reverse-mode Mooncake, ReverseDiff, and ForwardDiff.

```julia
model = normal_model(data)
# UseGraph() is the default, no need to set explicitly
```

## UseGeneratedLogDensityFunction

This mode generates and compiles a Julia function for the log density, which can be faster for some models.

```julia
model = normal_model(data)
model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
```

Use with Mooncake or another mutation-supporting backend for AD:

```julia
using ADTypes, Mooncake
model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```

## UseAutoMarginalization

For models with discrete latent variables, auto-marginalization enables gradient-based inference by marginalizing out discrete parameters. See [Auto-Marginalization](auto_marginalization.md) for details.

```julia
model = normal_model(data)
model = JuliaBUGS.settrans(model, true)  # requires transformed space
model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseAutoMarginalization())
```

## API

```@docs
JuliaBUGS.Model.set_evaluation_mode
```
