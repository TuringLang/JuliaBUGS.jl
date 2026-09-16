# Evaluation Modes

JuliaBUGS supports multiple evaluation modes that determine how the log density is computed. The evaluation mode also constrains which AD backends can be used.

## Compiled model contract

A compiled BUGS model represents a fixed program: its expressions and explicit
model inputs determine its density. Evaluation modes and serialization rebuild
executable code for that same program. BUGS primitives must retain their meaning;
changing values belong in model inputs, not hidden mutable globals.

The same requirement applies transitively to custom primitives and ordinary Julia
helpers used by `@model`. JuliaBUGS does not snapshot Julia method definitions.
After editing a helper, compile a new model and prepare its gradients again;
continued evaluation of an older model after such edits is unsupported. Restoring
a model requires compatible package and helper definitions.

MistyClosure specializations are created locally as argument types are encountered.
AD backends may be loaded after compiling the base model, before preparing its
gradient wrapper. Loading a backend does not require recompiling the base model.

For a package-level model constant, define its `@model` constructor in that
package, or pass `eval_module=@__MODULE__` to `compile`, with
`using JuliaBUGS.BUGSPrimitives` in that module.
During package precompilation, node evaluation uses ordinary Julia functions;
MistyClosures are created after loading the package. Prepare gradient wrappers at
runtime. Generated evaluation continues to resolve model functions in the
`JuliaBUGS` namespace; register custom primitives there before using that mode.

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
