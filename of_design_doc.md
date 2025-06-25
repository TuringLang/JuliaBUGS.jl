# Design Document: `of` Type System for JuliaBUGS

## Overview

The `of` type system provides a declarative way to specify parameter **types** for probabilistic programming. It serves as a lightweight type annotation system that:
- Returns actual Julia types (not instances) that can be used in type annotations
- Encodes specifications (dimensions, bounds) in type parameters
- Provides utilities for parameter manipulation

## Core Concepts

### 1. Type-Based Design

The `of` function returns types with specifications encoded in type parameters:
- `of(Array, dims...)` → `OfArray{Float64, N, (dim1, dim2, ...)}` - Arrays with specified dimensions
- `of(Array, T, dims...)` → `OfArray{T, N, (dim1, dim2, ...)}` - Typed arrays
- `of(Real)` → `OfReal{Nothing, Nothing}` - Unbounded real numbers
- `of(Real, lower, upper)` → `OfReal{Val{lower}, Val{upper}}` - Bounded real numbers
- `of(Int)` → `OfInt{Nothing, Nothing}` - Unbounded integers
- `of(Int, lower, upper)` → `OfInt{Val{lower}, Val{upper}}` - Bounded integers
- `@of(field1=..., field2=...)` → `OfNamedTuple{(:field1, :field2), Tuple{Type1, Type2}}` - Named tuples (use @of macro only)
- `of(...; constant=true)` → `OfConstantWrapper{T}` - Marks a type as constant/hyperparameter (only supported for `Int` and `Real` types)

### 2. Type Parameter Encoding

The system encodes extra useful information into type parameters:
- **Dimensions**: Stored as tuple type parameters (e.g., `(3, 4)` for a 3×4 matrix)
- **Bounds**: Encoded using `Val{x}` for numeric bounds or `Nothing` for unbounded
- **Symbolic references**: Encoded using `SymbolicRef{:symbol}` for referencing other fields
- **Field names**: Stored as tuple of symbols in `OfNamedTuple`
- **Element types**: Preserved as type parameters for arrays and nested structures

### 3. Operations on Types

- `T(;kwargs...)` where `T<:OfType` - Constructor syntax to create types with specified constants

- `rand(T::Type{<:OfType})` - Generate random values matching the type specification
- `zero(T::Type{<:OfType})` - Generate zero/default values 
- `size(T::Type{<:OfType})` - Get dimensions/shape of the type
- `length(T::Type{<:OfType})` - Get total number of elements when flattened

- `flatten(T::Type{<:OfType}, values)` - Convert structured values to flat vector
- `unflatten(T::Type{<:OfType}, vec)` - Reconstruct structured values from flat vector

### 4. The @of Macro

The `@of` macro provides cleaner syntax by automatically converting field references to symbols:

```julia
T = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)  # 'n' is automatically converted to :n
)
```

### 5. Symbolic Dimensions and Bounds

For cases where dimensions need to be specified at runtime:

```julia
# Define type with symbolic dimensions using @of macro
MatrixType = @of(
    rows=of(Int; constant=true),
    cols=of(Int; constant=true),
    data=of(Array, rows, cols),  # Direct references converted to symbols
)
# Note: Expressions like 'rows + 1' are not yet supported

# Create concrete type by specifying constants
ConcreteType = MatrixType(;rows=3, cols=4)
# Can also validate data while concretizing
ConcreteType = MatrixType(;rows=3, cols=4, data=rand(3, 4))  # Validates that data matches 3x4
data_nt = (data=rand(3, 4),)
flat = flatten(ConcreteType, data_nt)
reconstructed = unflatten(ConcreteType, flat)

SemiConcreteType = MatrixType(; rows=3) # this will return a type with `cols` eliminated

# rand and zero will first concretize the type and call rand
rand(MatrixType(; rows=3, cols=4))
zero(MatrixType(; rows=10, cols=5))

rand(MatrixType(; rows=3)) # this would fail because some `Constant`s are not specified
```

## Example Usage

### Hierarchical Linear Model

Consider a hierarchical model for test scores across multiple schools:

**Model:**

$$
\begin{align}
y_{ij} &\sim \text{Normal}(\mu_j + x_{ij}'\beta, \sigma^2) && \text{Student } i \text{ in school } j \\
\mu_j &\sim \text{Normal}(\mu_0, \tau^2) && \text{School } j \text{ effect} \\
\beta &\sim \text{Normal}(0, 100) && \text{Regression coefficients} \\
\mu_0 &\sim \text{Normal}(0, 100) && \text{Grand mean} \\
\tau^2 &\sim \text{InverseGamma}(0.001, 0.001) && \text{Between-school variance} \\
\sigma^2 &\sim \text{InverseGamma}(0.001, 0.001) && \text{Within-school variance}
\end{align}
$$

Where:
- $y_{ij}$ is the test score for student $i$ in school $j$
- $x_{ij}$ are student-level covariates
- $\mu_j$ is the random effect for school $j$
- $\beta$ are fixed effects for covariates

**Implementation with `of` type system:**

```julia
ParamsType = @of(
    mu0=of(Real),
    beta=of(Array, Float64, 3),
    tau2=of(Real, 0, nothing),
    sigma2=of(Real, 0, nothing),
    school_effects=of(Array, 10),
    y=of(Array, 100),
)

params_rand = rand(ParamsType)
params_zero = zero(ParamsType)

user_input = (
    mu0=75.0,
    beta=[2.1, -0.5, 1.3],
    tau2=25.0,
    sigma2=100.0,
    school_effects=randn(10) * 5,
    y=randn(100) * 10 .+ 75,
)

InferredType = of(user_input) # the bounds of Real won't be inferred

size(ParamsType)
length(ParamsType)

flat_params = flatten(ParamsType, params)
new_flat_params = flat_params .* 0.9
new_params = unflatten(ParamsType, new_flat_params)

@model function school_model(
    (; mu0, beta, tau2, sigma2, school_effects, y)::ParamsType,
    X,
    school_id,
    n_students,
)
    # Priors
    mu0 ~ Normal(0, 100)
    beta ~ MvNormal(zeros(3), 100 * I)
    tau2 ~ InverseGamma(0.001, 0.001)
    sigma2 ~ InverseGamma(0.001, 0.001)

    # Random effects
    for j in 1:10
        school_effects[j] ~ Normal(mu0, sqrt(tau2))
    end

    # Likelihood
    for i in 1:n_students
        j = school_id[i]
        mean_i = school_effects[j] + dot(X[i, :], beta)
        y[i] ~ Normal(mean_i, sqrt(sigma2))
    end
end
```

### Model with Variable Dimensions

Here's an example of a model where array dimensions depend on other parameters:

```julia
# Mixture model where the number of mixture components is itself a parameter
Tparams = @of(
    n_components=of(Int, 1, 3; constant=true),  # Can be 1, 2, or 3
    weights=of(Array, n_components),            # Size depends on n_components
    means=of(Array, n_components),              # Size depends on n_components
    y=of(Array, 100)                            # Observations
)

@model function dynamic_mixture((; n_components, weights, means, y)::Tparams, n_obs)
    # Prior on component probabilities (Dirichlet)
    if n_components == 1
        weights[1] = 1.0  # Single component has weight 1
        means[1] ~ Normal(0.0, 1.0)
        for i in 1:n_obs
            y[i] ~ Normal(means[1], 0.5)
        end
    elseif n_components == 2
        # Two components
        weights ~ Dirichlet([1.0, 1.0])
        means[1] ~ Normal(-1.0, 1.0)
        means[2] ~ Normal(1.0, 1.0)
        # Mixture likelihood
        for i in 1:n_obs
            z ~ Categorical(weights)
            y[i] ~ Normal(means[z], 0.5)
        end
    else  # n_components == 3
        # Three components
        weights ~ Dirichlet([1.0, 1.0, 1.0])
        means[1] ~ Normal(-2.0, 1.0)
        means[2] ~ Normal(0.0, 1.0)
        means[3] ~ Normal(2.0, 1.0)
        # Mixture likelihood
        for i in 1:n_obs
            z ~ Categorical(weights)
            y[i] ~ Normal(means[z], 0.5)
        end
    end
end

# Another example: Variable-order autoregressive model
ARParams = @of(
    order=of(Int, 1, 5; constant=true),  # AR order between 1 and 5
    coeffs=of(Array, order),             # AR coefficients
    sigma=of(Real, 0, nothing),          # Error variance
    y=of(Array, 100),                    # Time series data
)

@model function variable_order_ar((; order, coeffs, sigma, y)::ARParams, n_obs)
    # Priors
    for i in 1:order
        coeffs[i] ~ Normal(0.0, 0.5)  # Shrinkage prior on AR coefficients
    end
    sigma ~ InverseGamma(2.0, 1.0)
    
    # AR likelihood
    for t in (order+1):n_obs
        # Compute AR prediction
        pred = 0.0
        for i in 1:order
            pred += coeffs[order+1-i] * y[t-i]
        end
        y[t] ~ Normal(pred, sqrt(sigma))
    end
end

# Usage example
# Concrete type with specific dimensions
ConcreteARType = ARParams(; order=3)
# This creates a type where coeffs has size 3

params = ConcreteARType(;coeffs=[0.5, -0.3, 0.1], sigma=0.25, y=randn(100))
```
