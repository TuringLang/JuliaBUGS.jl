# How to Specify and Create a `BUGSModel`

Creating a `BUGSModel` requires two key components: a BUGS program that defines the model structure and values for specific variables that parameterize the model.

To understand how to specify a model properly, it is important to distinguish between the different types of values you can provide to the JuliaBUGS compiler:

* **Constants**: Values used in loop bounds and index resolution
  * These are essential for model specification as they determine the model's dimensionality (how many variables are created) and establish the dependency structure between variables
  
* **Independent variables** (also called features, predictors, or covariates): Non-stochastic inputs required for forward simulation of the model
  * Examples include predictor variables in a regression model or time points in a time series model

* **Observations**: Values for stochastic variables that you wish to condition on
  * These are not necessary to specify the model structure, but when provided, they become the data that your model is conditioned on
  * (Note: In some advanced cases, stochastic variables can contribute to the log density without being part of a strictly generative model)

* **Initialization values**: Starting points for MCMC sampling
  * While optional in many cases, some models (particularly those with weakly informative priors or complex structures) require carefully chosen initialization values for effective sampling

## Syntax from previous BUGS softwares and their R packages

Traditionally, BUGS models were created through a software interface following these steps:
1. Write the model in a text file
2. Check the model syntax (parsing)
3. Compile the model with program text and data
4. Initialize the sampling process (optional)

R interface packages for BUGS maintained this workflow pattern through text-based interfaces that closely mirrored the original software.

JuliaBUGS initially adopted this familiar workflow to accommodate users with prior BUGS experience. Specifically, JuliaBUGS provides a `@bugs` macro that accepts model definitions either as strings or within a `begin...end` block:

```julia
# Example using string macro
@bugs"""
model {
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma <- 1 / sqrt(tau)
}
"""

# Example using block macro
@bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] +
                        b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0e-6)
    alpha1 ~ dnorm(0.0, 1.0e-6)
    alpha2 ~ dnorm(0.0, 1.0e-6)
    alpha12 ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

In both cases, the macro returns a Julia AST representation of the model. The `compile` function then takes this AST and user-provided values (as a `NamedTuple`) to create a `BUGSModel` instance.

While we maintain this interface for compatibility, we now also offer a more idiomatic Julia approach.

## The Interface

JuliaBUGS provides a Julian interface inspired by Turing.jl's model macro syntax. The `@model` macro creates a "model creating function" that returns a model object supporting operations like `AbstractMCMC.sample` (which samples MCMC chains) and `condition` (which modifies the model by incorporating observations).

### The `@model` Macro

The `@model` macro provides a Julia-native interface for defining probabilistic models using external type definitions.

#### External Type Definition with `@of`

```julia
# Define parameter types
SeedsParams = @of(
    r = of(Array, Int, 21),
    b = of(Array, 21),
    alpha0 = of(Real),
    alpha1 = of(Real),
    alpha2 = of(Real),
    alpha12 = of(Real),
    tau = of(Real, 0, nothing)
)

# Use in model
JuliaBUGS.@model function seeds(
    (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::SeedsParams,
    x1, x2, N, n
)    
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```

#### Function Signature Requirements

1. **First argument**: Declares stochastic parameters (variables defined with `~`)
   - Named tuple destructuring with type annotation: `(; param1, param2, ...)::TypeName`
   
2. **Remaining arguments**: All constants and independent variables required by the model

**Note**: Inline `of` type annotations (e.g., `(; param::of(Real))`) are not supported. Use external type definitions with the `@of` macro instead.

#### The `of` Type System

The `of` function creates type specifications for parameters:

- `of(Real)` - Unbounded real number
- `of(Real, lower, upper)` - Bounded real number
- `of(Int)` - Unbounded integer  
- `of(Int, lower, upper)` - Bounded integer
- `of(Array, dims...)` - Array with specified dimensions (defaults to Float64)
- `of(Array, T, dims...)` - Array with element type T

For models with variable dimensions, use the `@of` macro to create types with symbolic dimensions:

```julia
DynamicModel = @of(
    n = of(Int; constant=true),      # Constant (not sampled)
    coeffs = of(Array, n),           # Array with symbolic dimension
    sigma = of(Real, 0, nothing)     # Positive real
)
```

#### Creating Model Instances

To create model instances, you can provide parameter values as a `NamedTuple` or use the `unflatten` function for convenient initialization:

```julia
# Method 1: Provide specific parameter values
model = my_model((; param1=value1, param2=value2), constants...)

# Method 2: Use unflatten with missing values for initialization
using JuliaBUGS: unflatten
params = unflatten(of(MyParamType; n=5), missing)  # Creates instance with missing values
model = my_model(params, constants...)

# Method 3: Empty NamedTuple (all parameters sampled from prior)
model = my_model((;), constants...)
```

The `unflatten` function is particularly useful for creating parameter instances when you need to specify constant values but want missing values for stochastic parameters that will be sampled.

### Example

```julia
julia> # Define parameter types using @of macro
julia> SeedsParams = @of(
           r = of(Array, Int, 21),
           b = of(Array, 21),
           alpha0 = of(Real),
           alpha1 = of(Real),
           alpha2 = of(Real),
           alpha12 = of(Real),
           tau = of(Real, 0, nothing)
       )

julia> # Define model using external type definition
julia> @model function seeds(
        (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::SeedsParams,
        x1, x2, N, n
    )
        for i in 1:N
            r[i] ~ dbin(p[i], n[i])
            b[i] ~ dnorm(0.0, tau)
            p[i] = logistic(
                alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
            )
        end
        alpha0 ~ dnorm(0.0, 1.0E-6)
        alpha1 ~ dnorm(0.0, 1.0E-6)
        alpha2 ~ dnorm(0.0, 1.0E-6)
        alpha12 ~ dnorm(0.0, 1.0E-6)
        tau ~ dgamma(0.001, 0.001)
        sigma = 1 / sqrt(tau)
    end
seeds (generic function with 1 method)

julia> (; x1, x2, N, n) = JuliaBUGS.BUGSExamples.seeds.data; # extract data from existing BUGS example

julia> # Create model without observations (all parameters will be sampled from the prior generative process)
julia> m = seeds((;), x1, x2, N, n)
BUGSModel (parameters are in transformed (unconstrained) space, with dimension 47):

  Model parameters:
    alpha2
    b[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1]
    r[21], r[20], r[19], r[18], r[17], r[16], r[15], r[14], r[13], r[12], r[11], r[10], r[9], r[8], r[7], r[6], r[5], r[4], r[3], r[2], r[1]
    tau
    alpha12
    alpha1
    alpha0

julia> # Create model with observations for r
julia> r_data = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3]
julia> m_obs = seeds((r=r_data,), x1, x2, N, n)

julia> # Using unflatten for initialization with missing values
julia> using JuliaBUGS: unflatten
julia> params = unflatten(of(SeedsParams), missing)
julia> m_init = seeds(params, x1, x2, N, n)

julia> # Example with variable dimensions
julia> DynamicParams = @of(
           n = of(Int; constant=true),
           coeffs = of(Array, n),
           sigma = of(Real, 0, nothing),
           y = of(Array, 100)
       )

julia> @model function dynamic_regression(
        (; coeffs, sigma, y)::DynamicParams, 
        X, n
    )
        sigma ~ dgamma(0.001, 0.001)
        for i in 1:n
            coeffs[i] ~ dnorm(0, 0.001)
        end
        for i in 1:100
            y[i] ~ dnorm(coeffs[1] * X[i, 1], sigma)
        end
    end

julia> # Create concrete type with n=3 and initialize with missing values
julia> X = randn(100, 3)
julia> params = unflatten(of(DynamicParams; n=3), missing)
julia> model = dynamic_regression(params, X, 3)
```

### Common Patterns and Best Practices

#### Parameter Initialization

1. **Empty NamedTuple**: Use `(;)` when you want all parameters to be sampled from their priors
   ```julia
   model = my_model((;), data...)
   ```

2. **Partial Observations**: Provide only observed variables
   ```julia
   model = my_model((; observed_var=data), constants...)
   ```

3. **Missing Value Initialization**: Use `unflatten` when you need to specify constants but want missing stochastic parameters
   ```julia
   params = unflatten(of(MyParams; n=10), missing)
   model = my_model(params, constants...)
   ```
