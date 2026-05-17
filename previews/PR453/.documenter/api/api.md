
# API {#API}

## Model Definition and Compilation {#Model-Definition-and-Compilation}
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
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/parser/bugs_macro.jl#L163-L177" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.@model' href='#JuliaBUGS.@model'><span class="jlbinding">JuliaBUGS.@model</span></a> <Badge type="info" class="jlObjectType jlMacro" text="Macro" /></summary>



```julia
@model function_definition
```


Define a probabilistic model using JuliaBUGS syntax.

The `@model` macro transforms a function definition into a model-generating function. When called, this function returns a compiled `BUGSModel` object that can be used for inference.

**Function Signature**

The macro creates a function with this pattern:

```julia
@model function model_name(
    (; param1, param2, ...)::OptionalOfType,  # Stochastic parameters (first argument)
    constant1, constant2, ...                  # Constants and covariates
)
    # Model body with probabilistic statements using ~
end
```


This generates a function `model_name` that, when called with appropriate arguments, returns a `BUGSModel` instance.

**Arguments**
- **First argument**: A named tuple destructuring pattern for stochastic parameters
  - Must use the syntax `(; name1, name2, ...)`
    
  - Can optionally include an `of` type annotation like `(; x, y)::MyOfType`
    
  - Contains all variables that have probability distributions in the model
    
  
- **Remaining arguments**: Constants, covariates, and structural parameters
  - These are deterministic values that don&#39;t have distributions
    
  - Examples: covariate matrices, sample sizes, fixed hyperparameters
    
  

**Model Body**

Inside the model body, use the `~` operator to specify probability distributions:

```julia
y ~ dnorm(mu, tau)     # y follows a normal distribution
theta ~ dgamma(a, b)   # theta follows a gamma distribution
```


**Returns**

The generated function returns a `BUGSModel` object when called with appropriate arguments.

**Examples**

**Simple Linear Regression**

```julia
# Define the model-generating function
@model function regression(
    (; y, beta, sigma),  # y is observed data, beta and sigma are parameters
    X, N                 # X is covariate matrix, N is number of observations
)
    for i in 1:N
        mu[i] = X[i, :] ⋅ beta
        y[i] ~ dnorm(mu[i], sigma)
    end
    beta ~ dnorm(0, 0.001)
    sigma ~ dgamma(0.001, 0.001)
end

# Call the function to create a model instance
model = regression((; y = observed_data), X_matrix, length(observed_data))
# `model` is now a BUGSModel object
```


**With Type Specification**

```julia
# Define parameter structure
RegressionParams = @of(
    y = of(Array, Float64, 100),
    beta = of(Array, Float64, 3),
    sigma = of(Real, 0, nothing)
)

# Define the model-generating function with type annotation
@model function typed_regression(
    (; y, beta, sigma)::RegressionParams,
    X, N
)
    # Model body...
end

# Create a model instance
model = typed_regression((; y = data), X, N)
```


**Notes**
- The macro performs compile-time validation of the model structure
  
- Type annotations are validated after model compilation
  
- Only `of` types created with `@of` are supported for type annotations
  
- The first argument must always be a destructuring pattern, not a regular variable
  
- Each call to the generated function creates a new `BUGSModel` instance
  

See also: [`@bugs`](/two_macros#@bugs), [`compile`](/api/api#JuliaBUGS.compile), [`of`](/api/api#JuliaBUGS.of), [`@of`](/api/api#JuliaBUGS.@of)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/model_macro.jl#L3-L101" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.compile' href='#JuliaBUGS.compile'><span class="jlbinding">JuliaBUGS.compile</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
compile(model_def, data[, initial_params]; adtype=nothing)
```


Compile a BUGS model. Returns `BUGSModel`, or `BUGSModelWithGradient` if `adtype` is provided.

**Arguments**
- `model_def::Expr`: Model definition from `@bugs` macro
  
- `data::NamedTuple`: Observed data
  
- `initial_params::NamedTuple`: Initial parameter values (optional, defaults to prior samples)
  
- `adtype`: AD backend from ADTypes.jl (e.g., `AutoReverseDiff()`, `AutoForwardDiff()`, `AutoMooncake()`)
  

**Examples**

```julia
model = compile(model_def, data)
model = compile(model_def, data; adtype=AutoReverseDiff())
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/JuliaBUGS.jl#L238-L254" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.Model.initialize!' href='#JuliaBUGS.Model.initialize!'><span class="jlbinding">JuliaBUGS.Model.initialize!</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
initialize!(model::BUGSModel, initial_params::NamedTuple{<:Any, <:Tuple{Vararg{AllowedValue}}})
```


Initialize the model with a NamedTuple of initial values, the values are expected to be in the original space.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/model/bugsmodel.jl#L345-L349" target="_blank" rel="noreferrer">source</a></Badge>



```julia
initialize!(model::BUGSModel, initial_params::AbstractVector)
```


Initialize the model with a vector of initial values, the values can be in transformed space if `model.transformed` is set to true.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/model/bugsmodel.jl#L385-L389" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Type Specifications {#Type-Specifications}
<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.of' href='#JuliaBUGS.of'><span class="jlbinding">JuliaBUGS.of</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
of(T, args...; constant::Bool=false)
```


Create an `OfType` specification from various inputs.

**Main Methods**

**Arrays**

```julia
of(Array, dims...)              # Float64 array with given dimensions
of(Array, T, dims...)           # Array with element type T and given dimensions
```


**Real Numbers**

```julia
of(Float64)                     # Unbounded Float64
of(Float64, lower, upper)       # Bounded Float64
of(Float32)                     # Unbounded Float32
of(Float32, lower, upper)       # Bounded Float32
of(Real)                        # Unbounded Real (defaults to Float64)
of(Real, lower, upper)          # Bounded Real (defaults to Float64)
```


**Integers**

```julia
of(Int)                         # Unbounded integer
of(Int, lower, upper)           # Bounded integer
```


**Named Tuples**

```julia
of((;field1=spec1, field2=spec2, ...))  # NamedTuple with typed fields
```


**From Values (Type Inference)**

```julia
of(1.0)                         # Infers of(Float64)
of([1, 2, 3])                   # Infers of(Array, Int, 3)
of((a=1, b=2.0))               # Infers OfNamedTuple
```


**Arguments**
- `T`: Type to create specification for
  
- `args...`: Type-specific arguments (bounds, dimensions, etc.)
  
- `constant`: Mark type as constant/hyperparameter (default: false)
  

**Returns**

An `OfType` subtype encoding the specification in its type parameters.

**Examples**

```julia
# Basic types
T1 = of(Float64, 0, 1)          # OfReal{Float64, 0, 1}
T2 = of(Array, 3, 4)            # OfArray{Float64, 2, (3, 4)}
T3 = of(Int; constant=true)     # OfConstantWrapper{OfInt{Nothing, Nothing}}

# With @of macro for cleaner syntax
T4 = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)      # Symbolic dimension
)

# Type concretization
T5 = of(T4; n=10)               # Concrete type with n=10
```


**See also**

[`@of`](/api/api#JuliaBUGS.@of), [`OfType`](/api/api#JuliaBUGS.OfType)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L374-L442" target="_blank" rel="noreferrer">source</a></Badge>



```julia
of(model::BUGSModel)
```


Extract the `of` type specification from a compiled `BUGSModel`.

This function introspects the model&#39;s evaluation environment to reconstruct the corresponding  `of` type specification. This is useful for:
- Model introspection and debugging
  
- Type validation after compilation
  
- Generic code that needs to work with models without knowing their structure
  
- Model serialization and deserialization
  

**Arguments**
- `model::BUGSModel`: A compiled BUGS model
  

**Returns**
- An `OfNamedTuple` type representing the structure of all variables in the model
  

**Example**

```julia
# Define and compile a model
@model function regression((; y, beta, sigma), X, N)
    # ... model definition ...
end

model = regression((; y = data), X, N)

# Extract the of type from the compiled model
ModelType = of(model)
# ModelType might be: @of(y = of(Array, Float64, 100), beta = of(Array, Float64, 3), sigma = of(Real, 0, nothing))

# Use the extracted type
rand(ModelType)  # Generate random values matching the model structure
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L552-L586" target="_blank" rel="noreferrer">source</a></Badge>



```julia
of(::Type{T}, replacements::NamedTuple) where T<:OfType
of(::Type{T}; kwargs...) where T<:OfType
of(::Type{T}, pairs::Pair{Symbol}...) where T<:OfType
```


Create a concrete type by resolving symbolic dimensions and removing constants.

This function takes an `OfType` with symbolic dimensions or constants and creates a new type with some or all symbols resolved to concrete values. Constants that are provided are removed from the resulting type.

**Arguments**
- `T<:OfType`: The type to concretize
  
- `replacements`: Named tuple or keyword arguments mapping symbols to values
  

**Returns**

A new `OfType` with symbols replaced and constants removed.

**Examples**

```julia
# Define type with symbolic dimensions
T = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)
)

# Create concrete type
ConcreteT = of(T; n=10)      # @of(data=of(Array, 10, 2))

# Partial concretization
T2 = @of(
    rows = of(Int; constant=true),
    cols = of(Int; constant=true),
    matrix = of(Array, rows, cols)
)
Partial = of(T2; rows=5)     # @of(cols=of(Int; constant=true), matrix=of(Array, 5, :cols))
```


**See also**

[`of`](/api/api#JuliaBUGS.of), [`@of`](/api/api#JuliaBUGS.@of)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L623-L663" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.@of' href='#JuliaBUGS.@of'><span class="jlbinding">JuliaBUGS.@of</span></a> <Badge type="info" class="jlObjectType jlMacro" text="Macro" /></summary>



```julia
@of(field1=spec1, field2=spec2, ...)
```


Create an `OfNamedTuple` type with cleaner syntax for field references.

The `@of` macro provides a more intuitive syntax for creating named tuple types where fields can reference each other. Field names used in dimensions or bounds are automatically converted to symbolic references.

**Syntax**

```julia
@of(
    field_name = of_specification,
    ...
)
```


**Features**
- Direct field references without quoting (e.g., `n` instead of `:n`)
  
- Support for arithmetic expressions in dimensions (e.g., `n+1`, `2*n`)
  
- Automatic conversion to appropriate `OfNamedTuple` type
  
- Fields are processed in order, allowing later fields to reference earlier ones
  

**Examples**

```julia
# Basic usage with constants and arrays
T = @of(
    n = of(Int; constant=true),
    mu = of(Real),
    data = of(Array, n, 2)  # 'n' automatically converted to symbolic reference
)

# With arithmetic expressions
T = @of(
    n = of(Int; constant=true),
    original = of(Array, n, n),
    padded = of(Array, n+1, n+1),
    doubled = of(Array, 2*n, n)
)

# Nested structures
T = @of(
    dims = @of(
        rows = of(Int; constant=true),
        cols = of(Int; constant=true)
    ),
    matrix = of(Array, dims.rows, dims.cols)
)
```


**See also**

[`of`](/api/api#JuliaBUGS.of), [`OfNamedTuple`](/api/api#JuliaBUGS.OfNamedTuple)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L975-L1027" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.of-Tuple{JuliaBUGS.Model.BUGSModel}' href='#JuliaBUGS.of-Tuple{JuliaBUGS.Model.BUGSModel}'><span class="jlbinding">JuliaBUGS.of</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
of(model::BUGSModel)
```


Extract the `of` type specification from a compiled `BUGSModel`.

This function introspects the model&#39;s evaluation environment to reconstruct the corresponding  `of` type specification. This is useful for:
- Model introspection and debugging
  
- Type validation after compilation
  
- Generic code that needs to work with models without knowing their structure
  
- Model serialization and deserialization
  

**Arguments**
- `model::BUGSModel`: A compiled BUGS model
  

**Returns**
- An `OfNamedTuple` type representing the structure of all variables in the model
  

**Example**

```julia
# Define and compile a model
@model function regression((; y, beta, sigma), X, N)
    # ... model definition ...
end

model = regression((; y = data), X, N)

# Extract the of type from the compiled model
ModelType = of(model)
# ModelType might be: @of(y = of(Array, Float64, 100), beta = of(Array, Float64, 3), sigma = of(Real, 0, nothing))

# Use the extracted type
rand(ModelType)  # Generate random values matching the model structure
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L552-L586" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.OfType' href='#JuliaBUGS.OfType'><span class="jlbinding">JuliaBUGS.OfType</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
OfType
```


Abstract base type for all types in the `of` type system.

The `of` type system provides a declarative way to specify parameter types for  probabilistic programming. All `of` types encode their specifications (dimensions,  bounds, etc.) in type parameters, allowing them to be used as actual Julia types  in type annotations.

**Subtypes**
- `OfReal{T,Lower,Upper}`: Bounded or unbounded floating-point numbers
  
- `OfInt{Lower,Upper}`: Bounded or unbounded integers  
  
- `OfArray{T,N,Dims}`: Arrays with specified element type and dimensions
  
- `OfNamedTuple{Names,Types}`: Named tuples with typed fields
  
- `OfConstantWrapper{T}`: Wrapper marking a type as constant/hyperparameter
  

**See also**

[`of`](/api/api#JuliaBUGS.of), [`@of`](/api/api#JuliaBUGS.@of)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L7-L26" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='JuliaBUGS.OfNamedTuple' href='#JuliaBUGS.OfNamedTuple'><span class="jlbinding">JuliaBUGS.OfNamedTuple</span></a> <Badge type="info" class="jlObjectType jlType" text="Type" /></summary>



```julia
OfNamedTuple{Names,Types<:Tuple}
```


Type specification for named tuples with typed fields.

**Type Parameters**
- `Names`: Tuple of field names as symbols
  
- `Types<:Tuple`: Tuple of field types (each must be an `OfType`)
  

**Examples**

```julia
@of(mu=of(Real), tau=of(Real, 0, nothing))
of((a=of(Int), b=of(Array, 3, 3)))
```


**See also**

[`of`](/api/api#JuliaBUGS.of), [`@of`](/api/api#JuliaBUGS.@of)


<Badge type="info" class="source-link" text="source"><a href="https://github.com/TuringLang/JuliaBUGS.jl/blob/7cfd2fd7541439ba8715c4f6d7a85c1ad1746c6c/JuliaBUGS/src/of_type.jl#L150-L167" target="_blank" rel="noreferrer">source</a></Badge>

</details>

