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
- `of(Float64)` → `OfReal{Float64, Nothing, Nothing}` - Unbounded 64-bit floating point numbers
- `of(Float32)` → `OfReal{Float32, Nothing, Nothing}` - Unbounded 32-bit floating point numbers
- `of(Float64, lower, upper)` → `OfReal{Float64, lower, upper}` - Bounded 64-bit floats
- `of(Float32, lower, upper)` → `OfReal{Float32, lower, upper}` - Bounded 32-bit floats
- `of(Real)` → `OfReal{Float64, Nothing, Nothing}` - Unbounded real numbers (defaults to Float64 for backward compatibility)
- `of(Real, lower, upper)` → `OfReal{Float64, lower, upper}` - Bounded real numbers (defaults to Float64)
- `of(Int)` → `OfInt{Nothing, Nothing}` - Unbounded integers
- `of(Int, lower, upper)` → `OfInt{lower, upper}` - Bounded integers
- `@of(field1=..., field2=...)` → `OfNamedTuple{(:field1, :field2), Tuple{Type1, Type2}}` - Named tuples (use @of macro only)
- `of(...; constant=true)` → `OfConstantWrapper{T}` - Marks a type as constant/hyperparameter (supported for float types and Int)

### 2. Type Parameter Encoding

The system encodes extra useful information into type parameters:
- **Dimensions**: Stored as tuple type parameters (e.g., `(3, 4)` for a 3×4 matrix)
- **Bounds**: Numeric literals stored directly as type parameters (e.g., `0.0`, `1.0`), or `Nothing` for unbounded
- **Symbolic references**: Encoded using `SymbolicRef{:symbol}` for referencing other fields
- **Arithmetic expressions**: Encoded using `SymbolicExpr{expr}` for expressions like `n+1`, `2*n`, etc. Division operations must result in integers for array dimensions.
- **Field names**: Stored as tuple of symbols in `OfNamedTuple`
- **Element types**: Preserved as type parameters for arrays and nested structures

### 3. Operations on Types

- `T(;kwargs...)` where `T<:OfType` - Create instances with specified constants (returns values, not types). Uses `zero()` as default for missing values.
- `T(default_value; kwargs...)` where `T<:OfType` - Create instances with specified constants, and initialise all element values to `default_value`, e.g. `T(missing; kwargs...)` initialise all element values to `missing`. `T(...)` returns instances, not types.
- `of(T; kwargs...)` where `T<:OfType` - Create concrete types by resolving constants

- `rand(T::Type{<:OfType})` - Generate random values matching the type specification
- `zero(T::Type{<:OfType})` - Generate zero/default values 
- `size(T::Type{<:OfType})` - Get dimensions/shape of the type
- `length(T::Type{<:OfType})` - Get total number of elements when flattened

- `flatten(T::Type{<:OfType}, values)` - Convert structured values to flat vector
- `unflatten(T::Type{<:OfType}, vec)` - Reconstruct structured values from flat vector
- `unflatten(T::Type{<:OfType}, missing)` - Create instances where element values are initialised to `missing`. 

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
    data=of(Array, rows, cols),
)

# Create concrete type by resolving constants
ConcreteType = of(MatrixType; rows=3, cols=4)
# ConcreteType is @of(data=of(Array, 3, 4))

# Use concrete type with rand and zero
rand(ConcreteType)  # generates random 3×4 matrix wrapped in NamedTuple
zero(ConcreteType)  # generates zero 3×4 matrix wrapped in NamedTuple

# Partial concretization (semiconcretized)
SemiConcreteType = of(MatrixType; rows=3)
# SemiConcreteType is @of(cols=of(Int; constant=true), data=of(Array, 3, :cols))

# Create instance by providing all constants (default to zero for data)
instance = MatrixType(;rows=3, cols=4)  
# instance = (data = zeros(3, 4),)

# Create instance with missing values
instance = MatrixType(missing; rows=3, cols=4)  
# instance = (data = (3x4 matrix of `missing`s),)

# Create instance with specific data
instance = MatrixType(;rows=3, cols=4, data=rand(3, 4))  
# instance = (data = <provided 3x4 matrix>,)

# Create concrete type for flatten/unflatten
flat = flatten(ConcreteType, instance)
reconstructed = unflatten(ConcreteType, flat)

# rand and zero with concrete types
rand(of(MatrixType; rows=3, cols=4))  # generates random instance
zero(of(MatrixType; rows=10, cols=5)) # generates zero instance

# Missing constants will error
MatrixType(; rows=3) # Error: Constant `cols` is required but not provided
rand(MatrixType) # Error: Cannot generate random values for types with symbolic dimensions
```

```julia
ExpandedMatrixType = @of(
    n=of(Int; constant=true),
    original=of(Array, n, n),
    padded=of(Array, n+1, n+1),
    doubled=of(Array, 2*n, n),
    halved=of(Array, n/2, n),
)

# Create instance - all non-constant fields default to zero
instance = ExpandedMatrixType(; n=10)
# This creates an instance with:
# - original: 10×10 zero matrix
# - padded: 11×11 zero matrix
# - doubled: 20×10 zero matrix  
# - halved: 5×10 zero matrix  (n/2 must result in an integer, error if not)

# Create instance with custom default value
instance = ExpandedMatrixType(1.0; n=10)
# This creates an instance with all matrices filled with 1.0

# Generate random instance
rand(of(ExpandedMatrixType; n=10))
```

## Example Usage

### Static Model Specification

```julia
ParamsType = @of(
    mu0=of(Float64),
    beta=of(Array, Float64, 3),
    tau2=of(Float64, 0, nothing),
    sigma2=of(Float64, 0, nothing),
    school_effects=of(Array, 10),
    y=of(Array, Float32, 100),
)

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

#### Mixture Model

```julia
# Mixture model where the number of mixture components is itself a parameter
Tparams = @of(
    n_components=of(Int, 1, 3; constant=true),  # Can be 1, 2, or 3
    weights=of(Array, n_components),            # Size depends on n_components
    means=of(Array, n_components),              # Size depends on n_components
    y=of(Array, 100)                            # Observations
)

@model function dynamic_mixture((; weights, means, y)::Tparams, n_components, n_obs)
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
```

#### Variable-order autoregressive model

```julia
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
# Create instance with specific order
params = ARParams(; order=3)
# This creates an instance where coeffs has size 3, defaulting to zeros

# Or with specific values
params = ARParams(; order=3, coeffs=[0.5, -0.3, 0.1], sigma=0.25, y=randn(100))
```

#### Bayesian Nonparametric clustering model

```julia
# Dirichlet Process Mixture Model with truncation
DPMModel = @of(
    n_obs = of(Int, 10, 1000; constant=true),      # Number of observations
    n_features = of(Int, 1, 20; constant=true),    # Feature dimension
    max_clusters = of(Int, 10, 50; constant=true), # Truncation level for DP
    
    # Observed data (n_obs × n_features)
    data = of(Array, n_obs, n_features),
    
    # Cluster assignments (n_obs vector)
    z = of(Array, n_obs),
    
    # Stick-breaking weights (max_clusters - 1 vector)
    v = of(Array, max_clusters - 1),
    
    # Cluster weights derived from stick-breaking (max_clusters vector)
    weights = of(Array, max_clusters),
    
    # Cluster parameters: means (max_clusters × n_features)
    cluster_means = of(Array, max_clusters, n_features),
    
    # Cluster parameters: precisions (max_clusters vector)
    cluster_precs = of(Array, max_clusters),
    
    # Concentration parameter
    alpha = of(Real, 0.1, 10.0)
)

# Create instance with specific dimensions
instance = DPMModel(; n_obs=100, n_features=2, max_clusters=20)
# This creates an instance with (all defaulting to zero/appropriate defaults):
# - data: 100×2 array of observations
# - z: 100-element vector of cluster assignments
# - v: 19-element vector of stick-breaking proportions
# - weights: 20-element vector of cluster weights
# - cluster_means: 20×2 array of cluster centers
# - cluster_precs: 20-element vector of cluster precisions
# - alpha: concentration parameter

@model function dp_mixture(
    (;data, z, v, weights, cluster_means, cluster_precs, alpha)::DPMModel, 
    n_obs, n_features, max_clusters
)
    # Prior on concentration parameter
    alpha ~ Gamma(1.0, 1.0)
    
    # Stick-breaking construction for weights
    for k in 1:(max_clusters-1)
        v[k] ~ Beta(1.0, alpha)
    end
    
    # Compute weights from stick-breaking
    remaining = 1.0
    for k in 1:max_clusters
        if k < max_clusters
            weights[k] = v[k] * remaining
            remaining *= (1 - v[k])
        else
            weights[k] = remaining  # Last weight gets all remaining mass
        end
    end
    
    # Priors on cluster parameters
    for k in 1:max_clusters
        cluster_precs[k] ~ Gamma(1.0, 1.0)
        for d in 1:n_features
            cluster_means[k,d] ~ Normal(0.0, 10.0)
        end
    end
    
    # Data likelihood
    for i in 1:n_obs
        # Cluster assignment
        z[i] ~ Categorical(weights)
        
        # Observation given cluster
        for d in 1:n_features
            data[i,d] ~ Normal(cluster_means[z[i],d], 1/sqrt(cluster_precs[z[i]]))
        end
    end
end

# Create instance for 50 observations, up to 10 clusters
dpm = DPMModel(; n_obs=50, n_features=2, max_clusters=10)
```
