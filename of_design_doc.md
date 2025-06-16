# Design Document: `of` Type System for JuliaBUGS

## Overview

The `of` type system provides a declarative way to specify parameter **structure**s for probabilistic programming language. It serves as a lightweight type annotation system that:
- Enables clear parameter structure specification
- Supports automatic type validation and conversion
- Integrates seamlessly with Julia's type system and Functors.jl
- Provides utilities for parameter manipulation

## Core Concepts

### 1. Type Specifications

The `of` function creates type specifications:
- `of(Array, dims...)` - Arrays with specified dimensions (element type defaults to Any)
- `of(Array, T, dims...)` - Typed arrays with specific element type
- `of(Real)` - Unbounded real numbers (stored as Float64)
- `of(Real, lower, upper)` - Bounded real numbers with constraints
- `of((field1=..., field2=...))` - Named tuples (only container type supported)

### 2. Runtime vs Compile-time

The system supports both approaches through a "middle ground" design:
- **Runtime**: `of` returns instances (e.g., `OfArray{Float64,2}`) that store metadata
- **Compile-time**: `@of` macro wraps specifications in `TypeOf{T,S}` for type annotations
- Both approaches preserve the full specification for runtime operations

### 3. Integration with Functors.jl

The implementation leverages Functors.jl for tree operations:
- Leaf types (`OfArray`, `OfReal`) are marked with `@leaf` 
- `OfNamedTuple` implements custom `functor` method that enables deconstruction/reconstruction
- The `functor` method returns `(children, reconstruct)` for tree traversal
- Built-in functions like `fmap`, `fleaves` work seamlessly
- `flatten`/`unflatten` use Functors.jl internally for structure manipulation
- Users can apply Functors.jl operations directly to parameter values

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
# Define hierarchical model parameters
params_spec = of((
    # Fixed effects
    mu0 = of(Real),                      # Grand mean
    beta = of(Array, Float64, 3),        # Regression coefficients (3 covariates)
    
    # Variance components
    tau2 = of(Real, 0, nothing),         # Between-school variance
    sigma2 = of(Real, 0, nothing),       # Within-school variance
    
    # Random effects
    school_effects = of(Array, 10)       # School-specific intercepts (10 schools)
))

# Runtime operations
params = rand(params_spec)               # Generate random initial values
params_zero = zero(params_spec)          # Zero initialization

# Validate user input (e.g., from previous MCMC run)
user_input = (
    mu0 = 75.0,
    beta = [2.1, -0.5, 1.3],
    tau2 = 25.0,
    sigma2 = 100.0,
    school_effects = randn(10) * 5
)
validated_params = validate(params_spec, user_input)

# Flatten/unflatten for optimization
flat_params = flatten(params_spec, params)  # Extract numerical vector
println("Flattened parameters: ", length(flat_params), " values")

new_flat = flat_params .* 0.9  # Example transformation

# Reconstruct structured parameters
optimized_params = unflatten(params_spec, new_flat)

# Type annotation for model definition
SchoolParams = @of((
    mu0 = of(Real),
    beta = of(Array, Float64, 3),
    tau2 = of(Real, 0, nothing),
    sigma2 = of(Real, 0, nothing),
    school_effects = of(Array, 10)
))

@model function school_model(params::SchoolParams, data)
    (; mu0, beta, tau2, sigma2, school_effects) = params
    (; y, X, school_id, n_students) = data
    
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

# TODO: it should also support directly use `of` in type annotation
```
