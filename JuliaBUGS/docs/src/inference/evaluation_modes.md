# Evaluation Modes

JuliaBUGS supports multiple evaluation modes that determine how the log density is computed. The evaluation mode also constrains which AD backends can be used.

## Compiled model

A compiled BUGS model represents a fixed program **assuming the BUGS primitives and helpers used to compute its density are pure and retain stable semantics**. Pure means that the same input values produce the same result, without observable side effects or dependence on hidden mutable state. This requirement applies transitively to custom primitives and ordinary Julia helpers used by `@model`. Changing values belong in explicit model inputs, not hidden mutable globals.

Purity does not prevent a Julia method from being redefined. Definitions must also retain their meaning for the lifetime of a compiled model and when loading it from a saved file.

Stable helper semantics were already needed for reproducibility before the MistyClosure implementation (on `main` at commit `5b7bee3`). That implementation did not snapshot helper definitions: evaluation could observe redefinitions, and loading a saved model recompiled against the available definitions. MistyClosures make the timing different: cached specializations may retain old helper behavior, while new specializations or gradient preparation may use newer definitions. Neither implementation guarantees preservation of old helper behavior after redefinition.

### Source functions and execution

JuliaBUGS constructs an ordinary Julia function and retains it in an internal callable wrapper as `f.source`. For generated log-density evaluation, the function has this conceptual shape:

```julia
source = (evaluation_env, parameters) -> begin
    # Compute the model's log density using its data and parameters.
end
```

Here `evaluation_env` holds model values, including data. The wrapper retains the function object as `f.source`; it is not source text, typed SSA IR, or a Julia `@generated` function. Julia infers typed SSA IR for particular argument types and builds a cached MistyClosure. For example, `Float64` and `Float32` arguments may require separate specializations.

Mooncake differentiates `f.source` using available AD rules, rather than differentiating the execution caches. AD backends may be loaded after compiling the base model, before preparing its gradient wrapper. Loading a backend does not require recompiling the base model.

### Saving and loading

Saving a model retains its definition, data, and settings needed to reconstruct its functions; it does not preserve executable closures or the original Julia world age. When a saved model is loaded, for example in a new Julia session, JuliaBUGS reconstructs its ordinary Julia functions. MistyClosure specializations are then built as needed using the Julia methods available when they are prepared. Reproducing the same density and gradients requires compatible package and helper definitions and unchanged model data. Loading a saved gradient-enabled model also prepares its gradients again, so load the required AD backend before deserializing it.

### Editing helpers and package precompilation

Helper definitions are not snapshotted. After editing a helper, compile a new model and prepare its gradients again, using the same compilation options as appropriate for the original model:

```julia
using ADTypes, Mooncake

new_model = compile(model_def, data)
new_gradient_model = JuliaBUGS.BUGSModelWithGradient(
    new_model, AutoMooncake(; config=nothing)
)
```

Continued evaluation of an older model after such edits is unsupported. Pinning a Julia world age alone would not preserve helper definitions across Julia sessions, and world ages do not freeze mutable model data.

For a package-level model constant, define its `@model` constructor in that package, or pass `eval_module=@__MODULE__` to `compile`, with `using JuliaBUGS.BUGSPrimitives` in that module. During package precompilation, node evaluation uses ordinary Julia functions; MistyClosures are created after loading the package. Prepare gradient wrappers at runtime. Generated evaluation continues to resolve model functions in the `JuliaBUGS` namespace; register custom primitives there before using that mode.

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
