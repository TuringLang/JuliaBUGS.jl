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
- **Arithmetic expressions**: Encoded using `SymbolicExpr{expr}` for expressions like `n+1`, `2*n`, etc. Division operations must result in integers for array dimensions.
- **Field names**: Stored as tuple of symbols in `OfNamedTuple`
- **Element types**: Preserved as type parameters for arrays and nested structures

### 3. Operations on Types

- `T(;kwargs...)` where `T<:OfType` - Create instances with specified constants (returns values, not types)

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
    data=of(Array, rows, cols),
)

# Create instance by providing all constants (default to zero for data)
instance = MatrixType(;rows=3, cols=4)  
# instance = (data = zeros(3, 4),)

# Create instance with specific data
instance = MatrixType(;rows=3, cols=4, data=rand(3, 4))  
# instance = (data = <provided 3x4 matrix>,)

# Use flatten/unflatten with unconcretized types (providing constants as kwargs)
flat = flatten(MatrixType, instance; rows=3, cols=4)
reconstructed = unflatten(MatrixType, flat; rows=3, cols=4)

# rand and zero with keyword arguments
rand(MatrixType; rows=3, cols=4)  # generates random instance
zero(MatrixType; rows=10, cols=5) # generates zero instance

# Missing constants will error
MatrixType(; rows=3) # Error: Constant `cols` is required but not provided
rand(MatrixType; rows=3) # Error: Missing values for symbolic dimensions: cols
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

# Generate random instance
rand(ExpandedMatrixType; n=10)
```

## Example Usage

### Static Model Specification

```julia
ParamsType = @of(
    mu0=of(Real),
    beta=of(Array, Float64, 3),
    tau2=of(Real, 0, nothing),
    sigma2=of(Real, 0, nothing),
    school_effects=of(Array, 10),
    y=of(Array, 100),
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
