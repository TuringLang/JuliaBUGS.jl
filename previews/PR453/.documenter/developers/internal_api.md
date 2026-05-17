
# Internal API {#Internal-API}

Reference for internal-only symbols inside `JuliaBUGS.Parser`, `JuliaBUGS.Parser.CompilerUtils`, and `JuliaBUGS.Model`. These are not part of the public API and may change without notice.

## `JuliaBUGS.Parser` {#JuliaBUGS.Parser}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.to_julia_program' href='#JuliaBUGS.Parser.to_julia_program'><span class="jlbinding">JuliaBUGS.Parser.to_julia_program</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
to_julia_program
```


Convert a BUGS program to a Julia program.

**Arguments**
- `prog::String`: A string containing the BUGS program that needs to be converted.
  
- `replace_period::Bool=true`: A flag to determine whether periods should be replaced in the 
  

conversion process. If `true`, periods in variable names or other relevant places will be  replaced with an underscore. If `false`, periods will be retained, and variable name will be wrapped in `var"..."` to avoid syntax error.
- `no_enclosure::Bool=false`: A flag to determine the enclosure processing strategy. 
  

If `true`, the parse will not enforce the requirement that the program body to be enclosed in &quot;model { ... }&quot;. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/Parser.jl#L11-L26" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.@bugs' href='#JuliaBUGS.Parser.@bugs'><span class="jlbinding">JuliaBUGS.Parser.@bugs</span></a> <Badge type="info" class="jlObjectType jlMacro" text="Macro" /></summary>



```julia
@bugs(program::Expr)
@bugs(program::String; replace_period::Bool=true, no_enclosure::Bool=false)
```


Constructs a Julia Abstract Syntax Tree (AST) representation of a BUGS program. This macro supports two forms of input: a Julia expression or a string containing the BUGS program code. 
- When provided with a string, the macro parses it as a BUGS program, with optional arguments to control parsing behavior.
  
- When given an expression, it performs syntactic checks to ensure compatibility with BUGS syntax.
  

**Arguments for String Input**

For the string input variant, the following optional arguments are available:
- `replace_period::Bool`: When set to `true`, all periods (`.`) in the BUGS code are replaced. This is enabled by default.
  
- `no_enclosure::Bool`: When `true`, the parser does not require the BUGS program to be enclosed within `model{ ... }` brackets. By default, this is set to `false`.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/bugs_macro.jl#L163-L177" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## `JuliaBUGS.Parser.CompilerUtils` {#JuliaBUGS.Parser.CompilerUtils}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.concretize_colon_indexing-Tuple{Any, NamedTuple}' href='#JuliaBUGS.Parser.CompilerUtils.concretize_colon_indexing-Tuple{Any, NamedTuple}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.concretize_colon_indexing</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
concretize_colon_indexing(expr, eval_env::NamedTuple)
```


Replace all `Colon()`s in `expr` with the corresponding array size.

**Examples**

```julia
julia> concretize_colon_indexing(:(f(x[1, :])), (x = [1 2 3 4; 5 6 7 8; 9 10 11 12],))
:(f(x[1, 1:4]))
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L476-L486" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.concretize_eval_env-Tuple{NamedTuple}' href='#JuliaBUGS.Parser.CompilerUtils.concretize_eval_env-Tuple{NamedTuple}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.concretize_eval_env</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
concretize_eval_env(eval_env::NamedTuple)
```


For arrays in `eval_env`, if its `eltype` is `Union{Missing, T}` where `T` is a concrete type, then  it tries to convert the array to `AbstractArray{T}`. If the conversion is not possible, it leaves  the array unchanged.

**Examples**

```julia
julia> concretize_eval_env((a = Union{Missing,Int}[1, 2, 3],))
(a = [1, 2, 3],)

```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L58-L71" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.create_eval_env-Union{Tuple{non_data_array_vars}, Tuple{data_vars}, Tuple{Tuple{Vararg{Symbol}}, NamedTuple{non_data_array_vars}, NamedTuple{data_vars}}} where {data_vars, non_data_array_vars}' href='#JuliaBUGS.Parser.CompilerUtils.create_eval_env-Union{Tuple{non_data_array_vars}, Tuple{data_vars}, Tuple{Tuple{Vararg{Symbol}}, NamedTuple{non_data_array_vars}, NamedTuple{data_vars}}} where {data_vars, non_data_array_vars}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.create_eval_env</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
create_eval_env(non_data_scalars, non_data_array_sizes, data)
```


Constructs an `NamedTuple` containing all the variables defined or used in the program. 

Arrays given by data will only be copied if they contain `missing` values. This copy behavior ensures  that the evaluation environment is a self-contained snapshot, avoiding unintended side effects on the input data.

Variables not given by data will be assigned `missing` values.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L16-L25" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.decompose_for_expr-Tuple{Expr}' href='#JuliaBUGS.Parser.CompilerUtils.decompose_for_expr-Tuple{Expr}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.decompose_for_expr</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
decompose_for_expr(expr::Expr)
```


Decompose a for-loop expression into its components. The function returns four items: the  loop variable, the lower bound, the upper bound, and the body of the loop.

**Examples**

```julia
julia> ex = MacroTools.@q for i in 1:3
           x[i] = i
           for j in 1:3
               y[i, j] = i + j
           end
       end;

julia> loop_var, lb, ub, body = decompose_for_expr(ex);

julia> loop_var
:i

julia> lb
1

julia> ub
3

julia> body == MacroTools.@q begin
           x[i] = i
           for j in 1:3
               y[i, j] = i + j
           end
       end
true
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L88-L122" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims-Tuple{Expr}' href='#JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims-Tuple{Expr}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
extract_variable_names_and_numdims(expr::Expr)
```


Extract all the array variable names and number of dimensions. Inconsistent number of dimensions will raise an error.

**Example:**

```julia
extract_variable_names_and_numdims(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

(N = 0, T = 0, Y = 2, var"obs.t" = 1, eps = 0, t = 1, dN = 2, fail = 1, Idt = 2, Z = 1, beta = 0, dL0 = 1, mu = 1, c = 0, var"dL0.star" = 1, var"S.treat" = 1, var"S.placebo" = 1, r = 0)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L195-L234" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims-Tuple{Union{Float64, Int64}, Tuple{Vararg{Symbol}}}' href='#JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims-Tuple{Union{Float64, Int64}, Tuple{Vararg{Symbol}}}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.extract_variable_names_and_numdims</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
extract_variable_names_and_numdims(expr, excluded)
```


Extract all the array variable names and number of dimensions from a given simple expression. 

**Examples:**

```julia
julia> extract_variable_names_and_numdims(:((a + b) * c), ())
(a = 0, b = 0, c = 0)

julia> extract_variable_names_and_numdims(:((a + b) * c), (:a,))
(b = 0, c = 0)

julia> extract_variable_names_and_numdims(:(a[i]), ())
(a = 1, i = 0)

julia> extract_variable_names_and_numdims(:(a[i]), (:i,))
(a = 1,)

julia> extract_variable_names_and_numdims(42, ())
NamedTuple()

julia> extract_variable_names_and_numdims(:x, (:x,))
NamedTuple()

julia> extract_variable_names_and_numdims(:(x[1, :]), ())
(x = 2,)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L131-L159" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.extract_variables_assigned_to-Tuple{Expr}' href='#JuliaBUGS.Parser.CompilerUtils.extract_variables_assigned_to-Tuple{Expr}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.extract_variables_assigned_to</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
extract_variables_assigned_to(expr::Expr)
```


Returns four tuples contains the Symbol of the variable assigned to in the program. The first tuple contains the logical scalar variables, the second tuple contains the stochastic scalar variables, the third tuple contains the logical array variables, and the fourth tuple contains the stochastic array variables.

**Example:**

```julia
extract_variables_assigned_to(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

((:c, :r), (:beta,), (Symbol("dL0.star"), :dN, :mu, Symbol("S.treat"), Symbol("S.placebo"), :Y, :Idt), (:dN, :dL0))
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L388-L428" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.extract_variables_in_bounds_and_lhs_indices-Tuple{Expr}' href='#JuliaBUGS.Parser.CompilerUtils.extract_variables_in_bounds_and_lhs_indices-Tuple{Expr}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.extract_variables_in_bounds_and_lhs_indices</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
extract_variables_in_bounds_and_lhs_indices(expr::Expr)
```


Extract all the variable names used in the bounds and indices of the arrays in the program.

**Example:**

```julia
extract_variables_in_bounds_and_lhs_indices(
    @bugs begin
        for i in 1:N
            for j in 1:T
                Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j in 1:T
            for i in 1:N
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            dL0[j] ~ dgamma(mu[j], c)
            mu[j] = var"dL0.star"[j] * c
            var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        c = 0.001
        r = 0.1
        for j in 1:T
            var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
        beta ~ dnorm(0.0, 1.0e-6)
    end
)

# output

(:N, :T)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L286-L324" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Parser.CompilerUtils.simple_arithmetic_eval-Tuple{NamedTuple, Union{UnitRange{Int64}, Int64}}' href='#JuliaBUGS.Parser.CompilerUtils.simple_arithmetic_eval-Tuple{NamedTuple, Union{UnitRange{Int64}, Int64}}'><span class="jlbinding">JuliaBUGS.Parser.CompilerUtils.simple_arithmetic_eval</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
simple_arithmetic_eval(data, expr)
```


This function evaluates expressions that consist solely of arithmetic operations and indexing. It  is specifically designed for scenarios such as calculating array indices or determining loop boundaries.

**Example:**

```julia
julia> simple_arithmetic_eval((a = 1, b = [1, 2]), 1)
1

julia> simple_arithmetic_eval((a = 1, b = [1, 2]), :a)
1

julia> simple_arithmetic_eval((a = 1, b = [1, 2]), :(a + b[1]))
2
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/parser/utils.jl#L502-L519" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## `JuliaBUGS.Model` {#JuliaBUGS.Model}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.BUGSModelWithGradient' href='#JuliaBUGS.Model.BUGSModelWithGradient'><span class="jlbinding">JuliaBUGS.Model.BUGSModelWithGradient</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
BUGSModelWithGradient{AD,P,M}
```


Wrap a `BUGSModel` with AD capabilities for gradient-based inference.

Implements `LogDensityProblems.logdensity` and `LogDensityProblems.logdensity_and_gradient`.

**Fields**
- `adtype::AD`: AD backend (e.g., `AutoReverseDiff()`)
  
- `prep::P`: Prepared gradient from DifferentiationInterface
  
- `base_model::M`: The underlying `BUGSModel`
  

See also [`compile`](/api/api#JuliaBUGS.compile).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/logdensityproblems.jl#L65-L78" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.BUGSModelWithGradient-Tuple{JuliaBUGS.Model.BUGSModel, ADTypes.AbstractADType}' href='#JuliaBUGS.Model.BUGSModelWithGradient-Tuple{JuliaBUGS.Model.BUGSModel, ADTypes.AbstractADType}'><span class="jlbinding">JuliaBUGS.Model.BUGSModelWithGradient</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
BUGSModelWithGradient(model::BUGSModel, adtype::ADTypes.AbstractADType)
```


Construct a gradient-enabled model wrapper from a BUGSModel and an AD backend.

**AD Backend Compatibility**

Different AD backends have different compatibility with evaluation modes:
- **`UseGeneratedLogDensityFunction`**: Only compatible with mutation-supporting backends like `AutoMooncake` and `AutoEnzyme`. The generated functions mutate arrays in-place.
  
- **`UseGraph`**: Compatible with `AutoReverseDiff`, `AutoForwardDiff`, and other tape-based or forward-mode backends. Also works with Mooncake and Enzyme.
  

If an incompatible combination is detected, a warning is issued and the model is automatically switched to `UseGraph` mode.

**Example**

```julia
model = compile(model_def, data)
grad_model = BUGSModelWithGradient(model, AutoReverseDiff(compile=true))
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/logdensityproblems.jl#L85-L107" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.GraphEvaluationData' href='#JuliaBUGS.Model.GraphEvaluationData'><span class="jlbinding">JuliaBUGS.Model.GraphEvaluationData</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
GraphEvaluationData(g::BUGSGraph, [sorted_nodes], [active_parameters])
```


Create a `GraphEvaluationData` from a `BUGSGraph`, extracting and caching node information for efficient evaluation.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L54-L59" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.GraphEvaluationData-2' href='#JuliaBUGS.Model.GraphEvaluationData-2'><span class="jlbinding">JuliaBUGS.Model.GraphEvaluationData</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
GraphEvaluationData{TNF,TV}
```


Caches node information from the model graph to optimize evaluation performance. Stores pre-computed values to avoid repeated lookups from the MetaGraph during model evaluation.

**Fields**
- `sorted_nodes::Vector{<:VarName}`: Variables in topological order for evaluation
  
- `sorted_parameters::Vector{<:VarName}`: Parameters (unobserved stochastic variables) in sorted order consistent with sorted_nodes
  
- `is_stochastic_vals::Vector{Bool}`: Whether each node represents a stochastic variable
  
- `is_observed_vals::Vector{Bool}`: Whether each node is observed (has data)
  
- `node_function_vals::TNF`: Functions that define each node&#39;s computation
  
- `loop_vars_vals::TV`: Loop variables associated with each node
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L31-L44" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.MarginalizationCache' href='#JuliaBUGS.Model.MarginalizationCache'><span class="jlbinding">JuliaBUGS.Model.MarginalizationCache</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
MarginalizationCache
```


Caches precomputed data for automatic marginalization of discrete finite variables. This cache is computed lazily when switching to `UseAutoMarginalization` mode and must be invalidated when the graph structure changes (e.g., during conditioning).

**Fields**
- `minimal_cache_keys::Dict{Int,Vector{Int}}`: Maps node index to minimal frontier indices for memoization.
  
- `marginalization_order::Vector{Int}`: Optimized evaluation order that reduces frontier size.
  
- `node_types::Vector{Symbol}`: Node type for each node (`:deterministic`, `:discrete_finite`, `:discrete_infinite`, or `:continuous`).
  
- `param_lengths::Dict{VarName,Int}`: Transformed lengths for continuous parameters.
  
- `param_offsets::Dict{VarName,Int}`: Start index in flattened parameter vector for each continuous param.
  
- `n_discrete_finite::Int`: Number of discrete finite variables (for memo sizing).
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L6-L21" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='AbstractPPL.evaluate!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}' href='#AbstractPPL.evaluate!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}'><span class="jlbinding">AbstractPPL.evaluate!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
AbstractPPL.evaluate!!(model::BUGSModel, flattened_values::AbstractVector; temperature=1.0, transformed=model.transformed)
```


Evaluate model with the given parameter values.

**Arguments**
- `model`: The BUGSModel to evaluate
  
- `flattened_values`: Vector of parameter values (in transformed or untransformed space)
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether the input values are in transformed space (default model.transformed)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `logp`: Log joint density
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/abstractppl.jl#L732-L746" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='AbstractPPL.evaluate!!-Tuple{JuliaBUGS.Model.BUGSModel}' href='#AbstractPPL.evaluate!!-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">AbstractPPL.evaluate!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
AbstractPPL.evaluate!!(model::BUGSModel; temperature=1.0, transformed=model.transformed)
```


Evaluate model using current values in the evaluation environment.

**Arguments**
- `model`: The BUGSModel to evaluate
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether to compute log density in transformed space (default model.transformed)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `logp`: Log joint density
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/abstractppl.jl#L711-L724" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='AbstractPPL.evaluate!!-Tuple{Random.AbstractRNG, JuliaBUGS.Model.BUGSModel}' href='#AbstractPPL.evaluate!!-Tuple{Random.AbstractRNG, JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">AbstractPPL.evaluate!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
AbstractPPL.evaluate!!(rng::Random.AbstractRNG, model::BUGSModel; sample_observed=false)
```


Evaluate model using ancestral sampling from the given RNG.

**Arguments**
- `rng`: Random number generator for sampling
  
- `model`: The BUGSModel to evaluate
  
- `sample_observed`: If true, sample observed nodes; if false (default), keep observed data fixed. Latent variables are always sampled.
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether to compute log density in transformed space (default model.transformed)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `logp`: Log joint density (uses model.transformed to determine if transformed space)
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/abstractppl.jl#L678-L693" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._classify_node_type-Tuple{Any}' href='#JuliaBUGS.Model._classify_node_type-Tuple{Any}'><span class="jlbinding">JuliaBUGS.Model._classify_node_type</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_classify_node_type(dist)
```


Classify a distribution into node types for marginalization. Returns one of: :deterministic, :discrete_finite, :discrete_infinite, :continuous


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L292-L297" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._compute_marginalization_order-Tuple{JuliaBUGS.Model.BUGSModel, Vector{Symbol}, Vector{Vector{Int64}}}' href='#JuliaBUGS.Model._compute_marginalization_order-Tuple{JuliaBUGS.Model.BUGSModel, Vector{Symbol}, Vector{Vector{Int64}}}'><span class="jlbinding">JuliaBUGS.Model._compute_marginalization_order</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_compute_marginalization_order(model, node_types, stochastic_parents)
```


Compute a topologically-valid evaluation order that reduces the frontier size by placing discrete finite variables immediately before their observed dependents.

The heuristic iterates over observed nodes and places each node&#39;s discrete finite parents right before it. This keeps discrete variables in the frontier briefly. For models with shared discrete variables, more sophisticated ordering (e.g., min-degree) could further reduce frontier size, but this is NP-hard in general.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L437-L447" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._compute_node_types-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model._compute_node_types-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model._compute_node_types</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_compute_node_types(model::BUGSModel)
```


Compute node type classification for all nodes in the model. Returns a vector of symbols: `:deterministic`, `:discrete_finite`, `:discrete_infinite`, or `:continuous`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L308-L313" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._enumerate_discrete_values-Tuple{Distribution{Univariate, Discrete}}' href='#JuliaBUGS.Model._enumerate_discrete_values-Tuple{Distribution{Univariate, Discrete}}'><span class="jlbinding">JuliaBUGS.Model._enumerate_discrete_values</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_enumerate_discrete_values(dist)
```


Return the finite support for a discrete univariate distribution. Relies on Distributions.support to provide an iterable, finite range.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L282-L287" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._get_stochastic_parents_indices-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model._get_stochastic_parents_indices-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model._get_stochastic_parents_indices</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_get_stochastic_parents_indices(model::BUGSModel)
```


Get the stochastic parents (through deterministic nodes) for each node in the model. Returns a vector of index vectors aligned with sorted_nodes.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L334-L339" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._is_discrete_finite_distribution-Tuple{Any}' href='#JuliaBUGS.Model._is_discrete_finite_distribution-Tuple{Any}'><span class="jlbinding">JuliaBUGS.Model._is_discrete_finite_distribution</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_is_discrete_finite_distribution(dist)
```


Check if a distribution is discrete with finite support.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L261-L265" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._logdensity_for_gradient-Tuple{AbstractVector, JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model._logdensity_for_gradient-Tuple{AbstractVector, JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model._logdensity_for_gradient</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_logdensity_for_gradient(x, model)
```


Target function for gradient computation via DifferentiationInterface. The parameter vector `x` comes first (the argument to differentiate w.r.t.), and the model is passed as a constant context (not differentiated).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/logdensityproblems.jl#L145-L151" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._marginalize_recursive-Union{Tuple{T}, Tuple{JuliaBUGS.Model.BUGSModel, NamedTuple, AbstractVector{Int64}, AbstractVector{T}, Dict{VarName, Int64}, Dict{VarName, Int64}, Dict{Tuple{Int64, Tuple}, Tuple{T, T}}, Dict{Int64, Vector{Int64}}}} where T' href='#JuliaBUGS.Model._marginalize_recursive-Union{Tuple{T}, Tuple{JuliaBUGS.Model.BUGSModel, NamedTuple, AbstractVector{Int64}, AbstractVector{T}, Dict{VarName, Int64}, Dict{VarName, Int64}, Dict{Tuple{Int64, Tuple}, Tuple{T, T}}, Dict{Int64, Vector{Int64}}}} where T'><span class="jlbinding">JuliaBUGS.Model._marginalize_recursive</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_marginalize_recursive(model, env, remaining_indices, parameter_values,
                       param_offsets, var_lengths, memo, minimal_keys)
```


Recursively compute log probability by marginalizing over discrete finite variables.

Returns `(log_prior, log_lik)` where the total log joint is `log_prior + log_lik`. This separation allows for likelihood tempering.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L491-L499" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model._precompute_minimal_cache_keys-Tuple{JuliaBUGS.Model.BUGSModel, Vector{Int64}, Vector{Symbol}, Vector{Vector{Int64}}}' href='#JuliaBUGS.Model._precompute_minimal_cache_keys-Tuple{JuliaBUGS.Model.BUGSModel, Vector{Int64}, Vector{Symbol}, Vector{Vector{Int64}}}'><span class="jlbinding">JuliaBUGS.Model._precompute_minimal_cache_keys</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
_precompute_minimal_cache_keys(model, order, node_types, stochastic_parents)
```


Precompute minimal cache keys for memoization during marginalization.

For each node, the frontier includes discrete finite variables that:
1. Were processed earlier in the evaluation order
  
2. Have dependents still to be processed (i.e., are still &quot;live&quot;)
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L365-L373" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.evaluate_with_env!!' href='#JuliaBUGS.Model.evaluate_with_env!!'><span class="jlbinding">JuliaBUGS.Model.evaluate_with_env!!</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
function evaluate_with_env!!(
    model::BUGSModel,
    evaluation_env=smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols);
    temperature=1.0,
    transformed=true,
)
```


Evaluate model using current values in the evaluation environment.

**Arguments**
- `model`: The BUGSModel to evaluate
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether to compute log density in transformed space (default true)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L110-L128" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.evaluate_with_marginalization_values!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}' href='#JuliaBUGS.Model.evaluate_with_marginalization_values!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}'><span class="jlbinding">JuliaBUGS.Model.evaluate_with_marginalization_values!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
evaluate_with_marginalization_values!!(model, flattened_values; temperature=1.0)
```


Evaluate model with marginalization over discrete finite variables.

This is the main entry point for auto-marginalization. Discrete finite variables are summed out, while continuous parameters are read from `flattened_values` (which must be in transformed/unconstrained space).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L650-L658" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.evaluate_with_rng!!-Tuple{Random.AbstractRNG, JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model.evaluate_with_rng!!-Tuple{Random.AbstractRNG, JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model.evaluate_with_rng!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
evaluate_with_rng!!(
    rng::Random.AbstractRNG,
    model::BUGSModel;
    sample_observed=false,
    temperature=1.0,
    transformed=true,
)
```


Evaluate model using ancestral sampling from the given RNG.

**Arguments**
- `rng`: Random number generator for sampling
  
- `model`: The BUGSModel to evaluate
  
- `sample_observed`: If true, sample observed nodes; if false (default), keep observed data fixed at their data values. Latent variables are always sampled.
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether to compute log density in transformed space (default true)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L29-L50" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.evaluate_with_values!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}' href='#JuliaBUGS.Model.evaluate_with_values!!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}'><span class="jlbinding">JuliaBUGS.Model.evaluate_with_values!!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
evaluate_with_values!!(
    model::BUGSModel, 
    flattened_values::AbstractVector; 
    temperature=1.0,
    transformed=true
)
```


Evaluate model with the given parameter values.

**Arguments**
- `model`: The BUGSModel to evaluate
  
- `flattened_values`: Vector of parameter values (in transformed or untransformed space)
  
- `temperature`: Temperature for tempering the likelihood (default 1.0)
  
- `transformed`: Whether the input values are in transformed space (default true)
  

**Returns**
- `evaluation_env`: Updated evaluation environment
  
- `(logprior, loglikelihood, tempered_logjoint)`: NamedTuple of log densities
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/evaluation.jl#L180-L199" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.get_mutable_symbols-Tuple{Any}' href='#JuliaBUGS.Model.get_mutable_symbols-Tuple{Any}'><span class="jlbinding">JuliaBUGS.Model.get_mutable_symbols</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
get_mutable_symbols(data) -> Set{Symbol}
```


Identify all symbols in the evaluation environment that may be mutated during model evaluation.

When called with a model, extracts the graph evaluation data first.

This includes:
- Model parameters (stochastic nodes that are not observations)
  
- Deterministic (logical) nodes
  

Does NOT include:
- Observed data (remains constant during sampling)
  
- Constants defined outside the model
  

**Examples**

```julia
model_def = @bugs begin
    x ~ Normal(0, 1)  # parameter - mutable
    y = x^2           # deterministic - mutable
    z ~ Normal(y, 1)  # observed data - immutable
end
model = compile(model_def, (; z = 1.5))
mutable_syms = get_mutable_symbols(model.graph_evaluation_data)
# Returns: Set([:x, :y])
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/utils.jl#L82-L108" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.getparams' href='#JuliaBUGS.Model.getparams'><span class="jlbinding">JuliaBUGS.Model.getparams</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
getparams([T::Type], model::BUGSModel, evaluation_env=model.evaluation_env)
```


Extract parameter values from the model.

**Arguments**
- `T::Type`: Optional output type. If not specified, returns a `Vector{Float64}`.  If `T <: AbstractDict`, returns a dictionary with `VarName` keys and parameter values.
  
- `model::BUGSModel`: The BUGS model from which to extract parameters.
  
- `evaluation_env`: The evaluation environment to use for extracting parameter values.  Defaults to `model.evaluation_env`.
  

**Returns**
- If `T` is not specified: `Vector{Float64}` - A flattened vector containing all parameter  values in the order consistent with `LogDensityProblems.logdensity`.
  
- If `T <: AbstractDict`: A dictionary of type `T` with `VarName` keys and parameter values.
  

**Notes**
- If `model.transformed` is true, returns parameters in the transformed (unconstrained) space.
  
- If `model.transformed` is false, returns parameters in their original (constrained) space.
  

**Examples**

```julia
# Get parameters as a vector
params_vec = getparams(model)

# Get parameters as a dictionary
params_dict = getparams(Dict, model)

# Use a custom evaluation environment
params_vec = getparams(model, custom_env)
params_dict = getparams(Dict, model, custom_env)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L395-L428" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.initialize!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}' href='#JuliaBUGS.Model.initialize!-Tuple{JuliaBUGS.Model.BUGSModel, AbstractVector}'><span class="jlbinding">JuliaBUGS.Model.initialize!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
initialize!(model::BUGSModel, initial_params::AbstractVector)
```


Initialize the model with a vector of initial values, the values can be in transformed space if `model.transformed` is set to true.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L385-L389" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.initialize!-Tuple{JuliaBUGS.Model.BUGSModel, NamedTuple{<:Any, <:Tuple{Vararg{Union{Missing, Float64, Int64, AbstractArray{T} where T<:Union{Missing, Float64, Int64}}}}}}' href='#JuliaBUGS.Model.initialize!-Tuple{JuliaBUGS.Model.BUGSModel, NamedTuple{<:Any, <:Tuple{Vararg{Union{Missing, Float64, Int64, AbstractArray{T} where T<:Union{Missing, Float64, Int64}}}}}}'><span class="jlbinding">JuliaBUGS.Model.initialize!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
initialize!(model::BUGSModel, initial_params::NamedTuple{<:Any, <:Tuple{Vararg{AllowedValue}}})
```


Initialize the model with a NamedTuple of initial values, the values are expected to be in the original space.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L345-L349" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.parameters-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model.parameters-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model.parameters</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
parameters(model::BUGSModel)
```


Return a vector of `VarName` containing the names of the model parameters (unobserved stochastic variables).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L328-L332" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.reconstruct-Tuple{Any, Any, Any}' href='#JuliaBUGS.Model.reconstruct-Tuple{Any, Any, Any}'><span class="jlbinding">JuliaBUGS.Model.reconstruct</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
reconstruct([f, ]dist, val)
```


Reconstruct `val` so that it&#39;s compatible with `dist`.

If `f` is also provided, the reconstruct value will be such that `f(reconstruct_val)` is compatible with `dist`.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/utils.jl#L24-L31" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.regenerate_log_density_function-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model.regenerate_log_density_function-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model.regenerate_log_density_function</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
regenerate_log_density_function(model::BUGSModel; force::Bool=false)
```


Generate and attach a compiled log-density function for the model&#39;s current graph and evaluation environment.

Does not change the evaluation mode. When `force=false`, preserves an existing compiled function; when `force=true`, overwrites it if a new one can be generated. Returns the updated model (or the original if generation is not possible).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/abstractppl.jl#L648-L655" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.set_evaluation_mode-Tuple{JuliaBUGS.Model.BUGSModel, JuliaBUGS.Model.EvaluationMode}' href='#JuliaBUGS.Model.set_evaluation_mode-Tuple{JuliaBUGS.Model.BUGSModel, JuliaBUGS.Model.EvaluationMode}'><span class="jlbinding">JuliaBUGS.Model.set_evaluation_mode</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



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



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L532-L558" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.set_observed_values!-Tuple{JuliaBUGS.Model.BUGSModel, Dict{<:VarName}}' href='#JuliaBUGS.Model.set_observed_values!-Tuple{JuliaBUGS.Model.BUGSModel, Dict{<:VarName}}'><span class="jlbinding">JuliaBUGS.Model.set_observed_values!</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
set_observed_values!(model::BUGSModel, obs::Dict{<:VarName,<:Any})
```


Update values of observed stochastic variables without reconditioning or regenerating code.

Validates that each variable exists in the model, is stochastic, and is currently observed. Updates the evaluation environment in place and returns the updated model.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/abstractppl.jl#L622-L629" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.settrans' href='#JuliaBUGS.Model.settrans'><span class="jlbinding">JuliaBUGS.Model.settrans</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
settrans(model::BUGSModel, bool::Bool=!(model.transformed))
```


The `BUGSModel` contains information for evaluation in both transformed and untransformed spaces. The `transformed` field indicates the current &quot;mode&quot; of the model.

This function enables switching the &quot;mode&quot; of the model.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L512-L519" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.smart_copy_evaluation_env-Tuple{NamedTuple, Set{Symbol}}' href='#JuliaBUGS.Model.smart_copy_evaluation_env-Tuple{NamedTuple, Set{Symbol}}'><span class="jlbinding">JuliaBUGS.Model.smart_copy_evaluation_env</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
smart_copy_evaluation_env(env::NamedTuple, mutable_syms::Set{Symbol}) -> NamedTuple
```


Create a copy of the evaluation environment where only mutable parts are deep copied.

Immutable parts (like observed data) are shared between the original and copy, avoiding expensive memory allocations and copies.

**Arguments**
- `env`: The evaluation environment to copy
  
- `mutable_syms`: Set of symbols that need to be deep copied
  

**Returns**

A new NamedTuple with:
- Deep copies of mutable fields
  
- Shared references to immutable fields
  

**Examples**

```julia
env = (x = [1.0, 2.0], data = rand(10000), y = 3.0)
mutable_syms = Set([:x, :y])
new_env = smart_copy_evaluation_env(env, mutable_syms)
# new_env.x is a copy, new_env.data is the same object, new_env.y is a copy
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/utils.jl#L131-L155" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.variables-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.Model.variables-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.Model.variables</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
variables(model::BUGSModel)
```


Return a vector of `VarName` containing the names of all the variables in the model.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/bugsmodel.jl#L335-L339" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='LogDensityProblems.logdensity_and_gradient-Tuple{JuliaBUGS.Model.BUGSModelWithGradient, AbstractVector}' href='#LogDensityProblems.logdensity_and_gradient-Tuple{JuliaBUGS.Model.BUGSModelWithGradient, AbstractVector}'><span class="jlbinding">LogDensityProblems.logdensity_and_gradient</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
LogDensityProblems.logdensity_and_gradient(model::BUGSModelWithGradient, x)
```


Compute log density and its gradient using DifferentiationInterface.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/1ba128513bf6b03be2a53a614e2cdee2eb213876/JuliaBUGS/src/model/logdensityproblems.jl#L156-L160" target="_blank" rel="noreferrer">source</a></Badge>

</details>

