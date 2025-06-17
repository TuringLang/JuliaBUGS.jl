# Design Document: `of` Type System for JuliaBUGS

## Overview

The `of` type system provides a declarative way to specify parameter **types** for probabilistic programming. It serves as a lightweight type annotation system that:
- Returns actual Julia types (not instances) that can be used in type annotations
- Encodes specifications (dimensions, bounds) in type parameters
- Supports automatic type validation and conversion
- Integrates seamlessly with Julia's type system
- Provides utilities for parameter manipulation

## Core Concepts

### 1. Type-Based Design

The `of` function returns **types** (not instances) with specifications encoded in type parameters:
- `of(Array, dims...)` → `OfArray{Float64, N, (dim1, dim2, ...)}` - Arrays with specified dimensions
- `of(Array, T, dims...)` → `OfArray{T, N, (dim1, dim2, ...)}` - Typed arrays
- `of(Real)` → `OfReal{Nothing, Nothing}` - Unbounded real numbers
- `of(Real, lower, upper)` → `OfReal{Val{lower}, Val{upper}}` - Bounded real numbers
- `of((field1=..., field2=...))` → `OfNamedTuple{(:field1, :field2), Tuple{Type1, Type2}}` - Named tuples

### 2. Type Parameter Encoding

The system encodes runtime values into type parameters:
- **Dimensions**: Stored as tuple type parameters (e.g., `(3, 4)` for a 3×4 matrix)
- **Bounds**: Encoded using `Val{x}` for numeric bounds or `Nothing` for unbounded
- **Field names**: Stored as tuple of symbols in `OfNamedTuple`
- **Element types**: Preserved as type parameters for arrays and nested structures

### 3. Direct Type Usage

Since `of` returns types, they can be used directly in Julia's type system:
```julia
# Direct in type annotations
function process(x::OfReal{Nothing, Val{1.0}})
    # x is guaranteed to be a Float64 with upper bound 1.0
end

# In parametric types
struct MyModel{T<:OfArray{Float64, 2, (10, 10)}}
    weights::T
end

# Type aliases
const PositiveReal = OfReal{Val{0}, Nothing}
```

### 4. Operations on Types

The system provides operations that work with types rather than instances:

#### Type-level operations:
- `rand(T::Type{<:OfType})` - Generate random values matching the type specification
- `zero(T::Type{<:OfType})` - Generate zero/default values 
- `T(value)` where `T<:OfType` - Constructor syntax to validate and convert values to match specifications
- `julia_type(T::Type{<:OfType})` - Extract the corresponding Julia type
- `dimension(T::Type{<:OfType})` - Get dimensions/shape of the type
- `length(T::Type{<:OfType})` - Get total number of elements when flattened

#### Structure manipulation:
- `flatten(T::Type{<:OfType}, values)` - Convert structured values to flat vector
- `unflatten(T::Type{<:OfType}, vec)` - Reconstruct structured values from flat vector
- Tree traversal using type introspection

### 5. Limitations and Concerns

**Runtime bounds limitation**: The current design encodes bounds as type parameters using `Val`, which requires bounds to be compile-time constants. This means bounds cannot be determined at runtime from data or computed values. This is a fundamental limitation of the type-based approach, as type parameters in Julia must be immutable and known at compile time.

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
# Define hierarchical model parameter types
ParamsType = of((
    # Fixed effects
    mu0 = of(Real),                      # Grand mean
    beta = of(Array, Float64, 3),        # Regression coefficients (3 covariates)
    
    # Variance components
    tau2 = of(Real, 0, nothing),         # Between-school variance (≥ 0)
    sigma2 = of(Real, 0, nothing),       # Within-school variance (≥ 0)
    
    # Random effects
    school_effects = of(Array, 10)       # School-specific intercepts (10 schools)
))

# Runtime operations using types
params = rand(ParamsType)               # Generate random initial values
params_zero = zero(ParamsType)          # Zero initialization

user_input = (
    mu0 = 75.0,
    beta = [2.1, -0.5, 1.3],
    tau2 = 25.0,
    sigma2 = 100.0,
    school_effects = randn(10) * 5
)
validated_params = ParamsType(user_input)

# Get dimensions and sizes
println("Dimensions: ", dimension(ParamsType))
# Output: (mu0=(), beta=(3,), tau2=(), sigma2=(), school_effects=(10,))

println("Total parameters: ", length(ParamsType))
# Output: 15 (1 + 3 + 1 + 1 + 10)

# Flatten/unflatten for optimization
flat_params = flatten(ParamsType, validated_params)  # Extract numerical vector
println("Flattened parameters: ", length(flat_params), " values")

new_flat = flat_params .* 0.9  # Example transformation

# Reconstruct structured parameters
optimized_params = unflatten(ParamsType, new_flat)

# Direct use as type annotation
@model function school_model((; mu0, beta, tau2, sigma2, school_effects)::ParamsType, data)
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
```
