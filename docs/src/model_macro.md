# Defining Probabilistic Models with JuliaBUGS

JuliaBUGS provides the `@model` macro for defining probabilistic models in a Julia-native way. This guide explains how to create and use models effectively.

## Core Concepts

When defining a model, you work with two main categories of variables:

### 1. Stochastic Parameters
Variables that follow probability distributions, defined with the `~` operator:
- **Unobserved parameters**: Variables to be sampled during inference
- **Observed data**: Known values that the model conditions on

### 2. Constants and Covariates
Deterministic inputs that don't have probability distributions:
- **Covariates/predictors**: Input features like `x` in regression models
- **Structural constants**: Values that determine model structure (e.g., `N` for array sizes)
- **Fixed parameters**: Any other non-stochastic inputs

## The `@model` Macro

The `@model` macro creates a function that returns a `BUGSModel` object. Here's the basic syntax:

```julia
@model function model_name(
    (; param1, param2, ...),     # Stochastic parameters (first argument)
    constant1, constant2, ...     # Constants and covariates
)
    # Model definition using ~ for distributions
end
```

### Function Signature Rules

1. **First argument**: Must be a named tuple pattern for stochastic parameters
   - Simple form: `(; x, y, z)`
   - With type annotation: `(; x, y, z)::MyOfType`

2. **Remaining arguments**: All constants, covariates, and structural parameters

### Example: Linear Regression

```julia
@model function linear_regression(
    (; y, beta, sigma),    # y is data, beta and sigma are parameters
    X, N                   # X is covariate matrix, N is size
)
    for i in 1:N
        y[i] ~ dnorm(mu[i], sigma)
        mu[i] = X[i, :] ⋅ beta
    end
    beta ~ dnorm(0, 0.001)
    sigma ~ dgamma(0.001, 0.001)
end
```

## Type Specifications with `of`

JuliaBUGS provides an `of` type system for specifying parameter structures and constraints. For a comprehensive guide to the `of` type system, including advanced features like symbolic dimensions, arithmetic expressions, and dynamic model structures, see the [of Design Documentation](of_design_doc.md).

The `of` system serves two main purposes:
1. Documents the expected structure of parameters
2. Validates the model after compilation to ensure type safety

### Quick Example

```julia
# Define a type for regression parameters
RegressionParams = @of(
    y = of(Array, Float64, 100),   # Observed data (100 observations)
    beta = of(Array, Float64, 3),  # Regression coefficients (3 predictors)
    sigma = of(Real, 0, nothing)   # Positive standard deviation
)

# Use in model definition
@model function regression(
    (; y, beta, sigma)::RegressionParams,
    X, N, p
)
    # Model body...
end
```

When you provide an `of` type annotation, JuliaBUGS automatically validates the compiled model's evaluation environment against your type specification.

## Creating and Using Models

### Basic Model Creation

```julia
# Create model with no observations (sample from prior)
model = my_model((;), constants...)

# Create model with some observed values
model = my_model((; y = observed_data), constants...)

# Create model with all parameters specified
model = my_model((; param1 = val1, param2 = val2), constants...)
```

### Using `unflatten` for Initialization

The `unflatten` utility helps create parameter instances with missing values:

```julia
using JuliaBUGS: unflatten

# Create a parameter instance with all missing values
params = unflatten(MyParamType, missing)
model = my_model(params, constants...)

# This is useful for models that need initialization
```

## Complete Example: Hierarchical Model

Here's a complete example showing all the concepts together:

```julia
# Step 1: Define parameter types
HierarchicalParams = @of(
    # Data
    y = of(Array, Float64, 30),     # 30 observations
    
    # Group-level parameters
    theta = of(Array, Float64, 8),  # 8 groups/schools
    
    # Hyperparameters
    mu = of(Real),
    tau = of(Real, 0, nothing),
    sigma = of(Real, 0, nothing)
)

# Step 2: Define the model
@model function hierarchical(
    (; y, theta, mu, tau, sigma)::HierarchicalParams,
    group
)
    # Likelihood
    for i in 1:30
        y[i] ~ dnorm(theta[group[i]], sigma)
    end
    
    # Group effects
    for j in 1:8
        theta[j] ~ dnorm(mu, tau)
    end
    
    # Hyperpriors
    mu ~ dnorm(0, 0.001)
    tau ~ dgamma(0.001, 0.001)
    sigma ~ dgamma(0.001, 0.001)
end

# Step 3: Create and use the model
# Prepare data (example: 8 schools data)
y_obs = randn(30) .+ 0.5    # 30 student outcomes
group_ids = [1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 
             5,5,5, 6,6,6, 7,7,7, 8,8,8,8,8]  # School assignments

# Create model with observations
model = hierarchical(
    (; y = y_obs),              # Observe y, sample the rest
    group_ids                   # Covariate: group assignments
)
```

## Important Notes and Restrictions

1. **Type annotation support**: Only `of` types created with the `@of` macro are supported for type annotations. Regular Julia types will cause an error.

2. **No inline annotations**: Parameter destructuring doesn't support inline type annotations like `(; x::Float64)`. Use external type definitions instead.

3. **Validation timing**: Type validation occurs after model compilation, not at function definition time.
