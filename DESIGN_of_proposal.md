# Design Document: The `of` Type System for JuliaBUGS

## Overview

This document outlines the design and implementation of the `of` type system, which replaces the current `@parameters` macro with a more flexible and Julia-idiomatic approach to parameter specification in JuliaBUGS models. The system provides pytree-like composability for complex hierarchical parameter structures commonly found in probabilistic programming.

## Motivation

The current `@parameters` macro has several limitations:
1. It requires a separate struct definition outside the model
2. Type annotations are not supported
3. It doesn't integrate well with Julia's type system
4. Parameter initialization is awkward with `ParameterPlaceholder`
5. At least as of Julia v1.11, struct can't be redefined, which makes it difficult to use
6. No support for hierarchical or nested parameter structures

The `of` system addresses these issues by:
- Providing inline type specifications
- Supporting both tuple and named tuple destructuring
- Offering direct integration with Julia's type system
- Enabling natural parameter initialization with `rand()` and `zero()`
- Supporting arbitrary nesting and composition of parameter structures
- Providing pytree-like utilities for parameter manipulation

## Core Design

### 1. The `of` Type Constructor

The `of` function creates type specifications for BUGS parameters:

```julia
# Basic usage
of(Array, dims...)           # Array with specified dimensions
of(Array, T, dims...)        # Array with element type T
of(Real)                     # Scalar real number
of(Real, lower, upper)       # Bounded real number
```

### 2. Type Representations

The `of` function returns type objects that can be:
- Used to generate random values: `rand(of(Array, 3, 4))`
- Used to generate zero values: `zero(of(Real))`
- Used as type annotations in function signatures
- Combined into tuples and named tuples

### 3. Parameter Specifications

#### Use Case 1: Runtime Parameter Generation
```julia
x = of(Array, 8)
y = of(Array, of(Real), 4, 3)
w = of(Real, lower, upper)

# Create parameter tuple/named tuple
params = of((x, y, w))                    # Tuple
params = of((x=x, y=y, w=w))             # NamedTuple

# Use in model
model(rand(params), constants...)
```

#### Use Case 2: Type Annotations
```julia
# Tuple parameters
Tparameters = Tuple{of(Array, 8), of(Array, of(Real), 4, 3), of(Real, lower, upper)}

@model function demo((x, y, w)::Tparameters, constants...)
    # model body
end

# NamedTuple parameters
NTparameters = @NamedTuple{x::of(Array, 8), y::of(Array, of(Real), 4, 3), w::of(Real, lower, upper)}

@model function demo((;x, y, w)::NTparameters, constants...)
    # model body
end
```

#### Use Case 3: Direct Support in `@model`
```julia
# Tuple syntax
@model function demo(
    (x::of(Array, 8), y::of(Array, of(Real), 4, 3), w::of(Real, lower, upper)),
    constants...
)
    # model body
end

# NamedTuple syntax
@model function demo(
    (;x::of(Array, 8), y::of(Array, of(Real), 4, 3), w::of(Real, lower, upper)),
    constants...
)
    # model body
end
```

## Implementation Details

### Type Hierarchy

```julia
abstract type OfType end
abstract type OfLeaf <: OfType end      # Terminal nodes
abstract type OfContainer <: OfType end  # Container nodes

# Leaf types (terminal nodes)
struct OfArray{T,N} <: OfLeaf
    element_type::Type
    dims::NTuple{N,Int}
end

struct OfReal <: OfLeaf
    lower::Union{Nothing,Real}
    upper::Union{Nothing,Real}
end

# Container types
struct OfTuple{T<:Tuple} <: OfContainer
    types::T
end

struct OfNamedTuple{names,T<:Tuple} <: OfContainer
    types::T
end

struct OfVector{T} <: OfContainer
    element_type::OfType
    length::Union{Nothing,Int}
end

struct OfDict{K,V} <: OfContainer
    key_type::Type{K}
    value_type::OfType
    keys::Union{Nothing,Vector{K}}
end
```

### Key Functions

1. **Type Construction**
   ```julia
   of(::Type{Array}, dims::Int...) = OfArray{Any,length(dims)}(Any, dims)
   of(::Type{Array}, T::Type, dims::Int...) = OfArray{T,length(dims)}(T, dims)
   of(::Type{Real}, lower=nothing, upper=nothing) = OfReal(lower, upper)
   ```

2. **Random Value Generation**
   ```julia
   Base.rand(::OfArray{T,N}) where {T,N} = rand(T, dims...)
   Base.rand(::OfReal) = rand() # with bounds handling
   ```

3. **Zero Value Generation**
   ```julia
   Base.zero(::OfArray{T,N}) where {T,N} = zeros(T, dims...)
   Base.zero(::OfReal) = 0.0
   ```

4. **Type Conversion**
   ```julia
   Base.convert(::Type{Type}, of_type::OfType) = julia_type(of_type)
   ```

### Pytree-like Traversal Utilities

The system provides utilities for working with hierarchical parameter structures:

1. **Tree Traversal**
   ```julia
   is_leaf(of_type)                    # Check if node is terminal
   tree_leaves(of_type)                 # Collect all leaf nodes
   tree_structure(of_type)              # Extract structure without leaves
   tree_map(f, of_type)                 # Apply function to all leaves
   tree_map_with_path(f, of_type)       # Map with path tracking
   ```

2. **Flattening/Unflattening**
   ```julia
   leaves, structure = flatten(of_type)           # Decompose into leaves + structure
   reconstructed = unflatten(leaves, structure)   # Reconstruct from components
   ```

### Integration with `@model` Macro

The `@model` macro needs to be updated to:
1. Recognize `of` type annotations in parameter destructuring
2. Extract type information for parameter validation
3. Generate appropriate parameter handling code
4. Support both runtime and compile-time type specifications

## Examples in Probabilistic Programming

### Example 1: Hierarchical Linear Model
```julia
# Define parameter structure for hierarchical model
HLMParams = of((
    # Population-level parameters
    population = (
        mu = of(Real),                    # Global mean
        tau = of(Real, 0, nothing)        # Global precision
    ),
    # Group-level parameters
    groups = of(Vector, 
        of((
            alpha = of(Real),              # Group intercept
            beta = of(Array, 3)            # Group coefficients
        )), 
        10  # 10 groups
    ),
    # Individual-level parameters
    sigma = of(Real, 0, nothing)          # Observation noise
))

# Use in model
@model function hierarchical_model(params::HLMParams, X, y, group_id)
    (; population, groups, sigma) = params
    
    # Population priors
    population.mu ~ Normal(0, 100)
    population.tau ~ Gamma(0.01, 0.01)
    
    # Group-level priors
    for g in 1:10
        groups[g].alpha ~ Normal(population.mu, sqrt(1/population.tau))
        for j in 1:3
            groups[g].beta[j] ~ Normal(0, 10)
        end
    end
    
    # Likelihood
    sigma ~ InverseGamma(0.01, 0.01)
    for i in 1:length(y)
        g = group_id[i]
        mu_i = groups[g].alpha + dot(groups[g].beta, X[i, :])
        y[i] ~ Normal(mu_i, sigma)
    end
end

# Initialize parameters
params = rand(HLMParams)
model = hierarchical_model(params, X, y, group_id)
```

### Example 2: Neural Network with Structured Parameters
```julia
# Define neural network parameter structure
NNParams = of((
    layers = of(Vector,
        of((
            W = of(Array, Float32, 128, 128),  # Weight matrix
            b = of(Array, Float32, 128),       # Bias vector
            dropout = of(Real, 0, 1)           # Dropout rate
        )),
        3  # 3 hidden layers
    ),
    output = (
        W = of(Array, Float32, 10, 128),       # Output weights
        b = of(Array, Float32, 10)             # Output bias
    ),
    hyperparams = of(Dict, Symbol, of(Real, 0, 1), 
                     [:learning_rate, :momentum, :weight_decay])
))

# Parameter manipulation using pytree utilities
params = rand(NNParams)

# Apply weight decay to all weight matrices
decayed_params = tree_map(params) do leaf
    if leaf isa OfArray && length(leaf.dims) == 2  # Matrix
        # Apply L2 regularization conceptually
        return leaf  # In practice, would modify values
    else
        return leaf
    end
end

# Flatten for optimization
flat_params, structure = flatten(params)

# After optimization, reconstruct
optimized_params = unflatten(optimized_flat_params, structure)
```

### Example 3: Mixture Model with Variable Components
```julia
# Gaussian mixture model with unknown number of components
GMMParams = of((
    K = of(Real, 1, 20),                    # Number of components (discrete)
    weights = of(Array, 20),                # Component weights (simplex)
    components = of(Vector,
        of((
            mu = of(Array, 2),              # 2D mean
            precision = of(Array, 2, 2)     # Precision matrix
        )),
        20  # Maximum 20 components
    ),
    assignments = of(Array, Int, 1000)      # Cluster assignments
))

@model function gmm_model(params::GMMParams, data)
    (; K, weights, components, assignments) = params
    
    # Prior on number of components
    K ~ Poisson(5)
    K_int = Int(round(K))
    
    # Dirichlet prior on weights (only use first K_int)
    weights[1:K_int] ~ Dirichlet(K_int, 1.0)
    
    # Component priors
    for k in 1:K_int
        components[k].mu ~ MvNormal([0, 0], 100*I)
        components[k].precision ~ Wishart(2, I(2))
    end
    
    # Data likelihood
    for i in 1:length(data)
        assignments[i] ~ Categorical(weights[1:K_int])
        k = assignments[i]
        data[i] ~ MvNormal(components[k].mu, inv(components[k].precision))
    end
end
```

### Example 4: State Space Model
```julia
# Time-varying parameter model
SSMParams = of((
    initial_state = of(Array, 4),           # Initial hidden state
    states = of(Array, 4, 100),             # Hidden states over time
    transition = (
        A = of(Array, 4, 4),                # State transition matrix
        Q = of(Array, 4, 4)                 # Process noise covariance
    ),
    observation = (
        H = of(Array, 2, 4),                # Observation matrix
        R = of(Array, 2, 2)                 # Observation noise covariance
    )
))

# Transform parameters for different inference algorithms
function to_natural_parameters(params)
    tree_map_with_path(params) do path, leaf
        if :Q in path || :R in path
            # Transform covariance matrices to precision
            return leaf  # Transformation logic here
        else
            return leaf
        end
    end
end
```
