
# Evaluation Modes {#Evaluation-Modes}

JuliaBUGS supports multiple evaluation modes that determine how the log density is computed. The evaluation mode also constrains which AD backends can be used.

## Available Modes {#Available-Modes}

|                               Mode |                                            Description |              AD Backends |
| ----------------------------------:| ------------------------------------------------------:| ------------------------:|
|                       `UseGraph()` |                Traverses computational graph (default) | ReverseDiff, ForwardDiff |
| `UseGeneratedLogDensityFunction()` |              Compiles a Julia function for log density |                 Mooncake |
|         `UseAutoMarginalization()` | Graph traversal with discrete variable marginalization | ReverseDiff, ForwardDiff |


## UseGraph (Default) {#UseGraph-Default}

The default mode evaluates the log density by traversing the computational graph. Works with ReverseDiff and ForwardDiff.

```julia
model = compile(model_def, data)
# UseGraph() is the default, no need to set explicitly
```


## UseGeneratedLogDensityFunction {#UseGeneratedLogDensityFunction}

This mode generates and compiles a Julia function for the log density, which can be faster for some models.

```julia
model = compile(model_def, data)
model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
```


Use with Mooncake for AD:

```julia
model = BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```


## UseAutoMarginalization {#UseAutoMarginalization}

For models with discrete latent variables, auto-marginalization enables gradient-based inference by marginalizing out discrete parameters. See [Auto-Marginalization](auto_marginalization.md) for details.

```julia
model = compile(model_def, data)
model = settrans(model, true)  # requires transformed space
model = set_evaluation_mode(model, UseAutoMarginalization())
```


## API {#API}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.set_evaluation_mode' href='#JuliaBUGS.Model.set_evaluation_mode'><span class="jlbinding">JuliaBUGS.Model.set_evaluation_mode</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
set_evaluation_mode(model::BUGSModel, mode::EvaluationMode)
```


Set the evaluation mode for the `BUGSModel`.

The evaluation mode determines how the log-density of the model is computed. Possible modes are:
- `UseGeneratedLogDensityFunction()`: Uses a statically generated function for log-density computation. This is often faster but may not be available for all models. The function is generated when switching to this mode. If generation fails, a warning is issued and the mode defaults to `UseGraph()`.
  
- `UseGraph()`: Computes the log-density by traversing the model&#39;s graph structure. This is always available but might be slower.
  

**Arguments**
- `model::BUGSModel`: The BUGS model instance.
  
- `mode::EvaluationMode`: The desired evaluation mode.
  

**Returns**
- A new `BUGSModel` instance with the `evaluation_mode` field updated. If the original model is mutable, it might be modified in place.
  

**Examples**

```julia
# Assuming `model` is a compiled BUGSModel instance
model_with_graph_eval = set_evaluation_mode(model, UseGraph())
model_with_generated_eval = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/model/bugsmodel.jl#L532-L558" target="_blank" rel="noreferrer">source</a></Badge>

</details>

