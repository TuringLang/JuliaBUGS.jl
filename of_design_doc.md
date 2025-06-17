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

The system encodes extra useful information into type parameters:
- **Dimensions**: Stored as tuple type parameters (e.g., `(3, 4)` for a 3×4 matrix)
- **Bounds**: Encoded using `Val{x}` for numeric bounds or `Nothing` for unbounded
- **Field names**: Stored as tuple of symbols in `OfNamedTuple`
- **Element types**: Preserved as type parameters for arrays and nested structures

### 3. Direct Type Usage

Since `of` returns types, they can be used directly in Julia's type system:
```julia
function process(x::of(Real,nothing,1.0))
    # x is guaranteed to be a Float64 with upper bound 1.0
end

struct MyModel{T<:of(Array,Float64,10,10)}
    weights::T
end

const PositiveReal = of(Real,0,nothing)
```

### 4. Operations on Types

The system provides operations that work with types rather than instances:

#### Type-level operations:
- `rand(T::Type{<:OfType})` - Generate random values matching the type specification
- `zero(T::Type{<:OfType})` - Generate zero/default values 
- `T(value)` where `T<:OfType` - Constructor syntax to validate and convert values to match specifications
- `julia_type(T::Type{<:OfType})` - Extract the corresponding Julia type
- `size(T::Type{<:OfType})` - Get dimensions/shape of the type
- `length(T::Type{<:OfType})` - Get total number of elements when flattened

#### Structure manipulation:
- `flatten(T::Type{<:OfType}, values)` - Convert structured values to flat vector
- `unflatten(T::Type{<:OfType}, vec)` - Reconstruct structured values from flat vector
- Tree traversal using type introspection

### 5. Symbolic Dimensions with Constants

For cases where dimensions need to be specified at runtime:

```julia
# Define type with symbolic dimensions
MatrixType = of((
    rows=of(Constant),
    cols=of(Constant),
    data=of(Array, :rows, :cols),
))

rand(MatrixType; rows=3, cols=4)
zero(MatrixType; rows=10, cols=5)

rand(MatrixType; rows=3) # this would fail because some `Constant`s are not specified

# Create concrete type for use with flatten/unflatten
ConcreteType = of(MatrixType; rows=3, cols=4)
data = (data=rand(3, 4),)
flat = flatten(ConcreteType, data)
reconstructed = unflatten(ConcreteType, flat)
```

### 6. Limitations and Concerns

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
ParamsType = of((
    mu0=of(Real),
    beta=of(Array, Float64, 3),
    tau2=of(Real, 0, nothing),
    sigma2=of(Real, 0, nothing),
    school_effects=of(Array, 10),
    y=of(Array, 100),
))

params_rand = rand(ParamsType)
params_zero = zero(ParamsType)

julia_type(ParamsType)

user_input = (
    mu0=75.0,
    beta=[2.1, -0.5, 1.3],
    tau2=25.0,
    sigma2=100.0,
    school_effects=randn(10) * 5,
    y=randn(100) * 10 .+ 75,
)
params = ParamsType(user_input)

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
