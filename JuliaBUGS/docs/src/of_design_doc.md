# Using the `of` Type System in JuliaBUGS

!!! note "Implementation lives in AbstractPPL"
    As of JuliaBUGS v0.14.1 the `of` type system is implemented in
    [AbstractPPL.jl](https://github.com/TuringLang/AbstractPPL.jl) (≥ 0.15.3). JuliaBUGS
    re-exports `of` and `@of`, so the user-facing API documented in AbstractPPL is
    available directly from `JuliaBUGS`. The supporting names (`OfType`, `OfReal`, `OfInt`,
    `OfArray`, `OfNamedTuple`, `OfConstantWrapper`, `flatten`, `unflatten`, …) live in
    `AbstractPPL`. JuliaBUGS additionally provides `of(model::BUGSModel)` to extract an `of`
    specification from a compiled model.

    For the complete API reference, see the
    [AbstractPPL `of` Type System](https://turinglang.org/AbstractPPL.jl/dev/of/)
    documentation.

The `of` type system provides a declarative way to specify parameter **types** for
probabilistic programming. In JuliaBUGS it is used to annotate the first argument of a
`@model` function. The annotation documents the expected structure of the stochastic
parameters and is used after compilation to validate the model evaluation environment.

```@setup of
using AbstractPPL: flatten
using JuliaBUGS
using JuliaBUGS: unflatten
using Distributions
using Random
nothing # hide
```

## Quick reference

The `of` function returns schema **types** (not instances) with dimensions, bounds, and
field names encoded in type parameters:

```@example of
of(Float64)                  # unbounded 64-bit float
of(Float64, 0.0, 1.0)        # float in [0.0, 1.0]
of(Real)                     # unbounded real (defaults to Float64)
of(Real, 0, nothing)         # positive real

of(Int)                      # unbounded integer
of(Int, 1, 10)               # integer in [1, 10]
of(Int; constant=true)       # integer constant / hyperparameter

of(Array, 3, 4)              # 3×4 Float64 matrix
of(Array, Float32, 10)       # 10-element Float32 vector

T = @of(
    n = of(Int; constant=true),
    data = of(Array, n, 2)   # `n` is automatically converted to a symbolic reference
)
T
```

Common operations on types:

```@example of
# Create an instance with non-constant fields defaulting to zero
MatrixType = @of(
    rows = of(Int; constant=true),
    cols = of(Int; constant=true),
    data = of(Array, rows, cols),
)
instance = MatrixType(; rows=3, cols=4)

# Create a concrete type by resolving the constants
ConcreteType = of(MatrixType; rows=3, cols=4)

# Generate random values matching the concrete type
rand(MersenneTwister(0), ConcreteType)
```

```@example of
# Flatten and reconstruct structured values
flat = flatten(ConcreteType, instance)
reconstructed = unflatten(ConcreteType, flat)
reconstructed.data == instance.data
```

## Symbolic dimensions and bounds

Constants can be declared with `constant=true` and referenced in later array dimensions and
bounds. Arithmetic expressions are also supported:

```@example of
ExpandedType = @of(
    n = of(Int; constant=true),
    original = of(Array, n, n),
    padded = of(Array, n + 1, n + 1),
    doubled = of(Array, 2 * n, n),
)

# Resolve the constant to get a concrete type
ConcreteExpanded = of(ExpandedType; n=10)
map(size, rand(MersenneTwister(0), ConcreteExpanded))
```

## Using `of` with `@model`

Annotate the first argument of a `@model` function with an `of` type. JuliaBUGS validates
the compiled model against the annotation.

```@example of
RegressionParams = @of(
    y = of(Array, Float64, 100),     # observed data
    beta = of(Array, Float64, 3),    # regression coefficients
    sigma = of(Real, 0, nothing)     # positive standard deviation
)

@model function regression((; y, beta, sigma)::RegressionParams, X)
    for k in 1:3
        beta[k] ~ Normal(0, 10)
    end
    sigma ~ Exponential(1)
    for i in 1:100
        mean_i = X[i, 1] * beta[1] + X[i, 2] * beta[2] + X[i, 3] * beta[3]
        y[i] ~ Normal(mean_i, sigma)
    end
end

X = randn(MersenneTwister(0), 100, 3)
y_obs = randn(MersenneTwister(1), 100)
model = regression((; y=y_obs), X)
model isa JuliaBUGS.BUGSModel
```

!!! note
    JuliaBUGS currently supports `Float64` and `Int` arrays in the model evaluation
    environment. Use `of(Array, Float64, ...)` for observed arrays and parameters.

## Example: hierarchical model

```@example of
SchoolParams = @of(
    mu0 = of(Float64),
    beta = of(Array, Float64, 3),
    tau2 = of(Float64, 0, nothing),
    sigma2 = of(Float64, 0, nothing),
    school_effects = of(Array, 10),
    y = of(Array, Float64, 100),
)

@model function school_model(
    (; mu0, beta, tau2, sigma2, school_effects, y)::SchoolParams,
    X, school_id, n_students,
)
    mu0 ~ Normal(0, 100)
    for k in 1:3
        beta[k] ~ Normal(0, 10)
    end
    tau2 ~ InverseGamma(0.001, 0.001)
    sigma2 ~ InverseGamma(0.001, 0.001)
    for j in 1:10
        school_effects[j] ~ Normal(mu0, sqrt(tau2))
    end
    for i in 1:n_students
        j = school_id[i]
        mean_i = school_effects[j] + X[i, 1] * beta[1] + X[i, 2] * beta[2] + X[i, 3] * beta[3]
        y[i] ~ Normal(mean_i, sqrt(sigma2))
    end
end

X = randn(MersenneTwister(0), 100, 3)
school_id = rand(MersenneTwister(1), 1:10, 100)
y_obs = randn(MersenneTwister(2), 100)
school_model((; y=y_obs), X, school_id, 100) isa JuliaBUGS.BUGSModel
```

## Example: variable dimension model

Declare the dimension as a constant and reference it in the array specification. For the
model annotation, use a concrete type produced by resolving the constant:

```@example of
DynamicParams = @of(
    n = of(Int; constant=true),
    data = of(Array, n),
    mu = of(Real),
    sigma = of(Real, 0, nothing),
)
ConcreteDynamicParams = of(DynamicParams; n=50)

@model function normal_with_variable_size(
    (; data, mu, sigma)::ConcreteDynamicParams, n
)
    mu ~ Normal(0, 10)
    sigma ~ Exponential(1)
    for i in 1:n
        data[i] ~ Normal(mu, sigma)
    end
end

params = unflatten(ConcreteDynamicParams, missing)
normal_with_variable_size(params, 50) isa JuliaBUGS.BUGSModel
```

## Example: autoregressive model

This example uses a fixed-order AR(3) specification for valid BUGS syntax. The `of` type
still documents the array shapes:

```@example of
ARParams = @of(
    coeffs = of(Array, Float64, 3),
    sigma = of(Real, 0, nothing),
    y = of(Array, Float64, 100),
)

@model function ar3_model((; coeffs, sigma, y)::ARParams, n_obs)
    for i in 1:3
        coeffs[i] ~ Normal(0.0, 0.5)
    end
    sigma ~ InverseGamma(2.0, 1.0)
    for t in 4:n_obs
        pred = coeffs[1] * y[t - 1] + coeffs[2] * y[t - 2] + coeffs[3] * y[t - 3]
        y[t] ~ Normal(pred, sqrt(sigma))
    end
end

# Provide observed data for `y` and initialise the parameters with `missing`
params = merge(unflatten(ARParams, missing), (y=randn(MersenneTwister(0), 100),))
ar3_model(params, 100) isa JuliaBUGS.BUGSModel
```

## Example: truncated Dirichlet process mixture

The `of` type system can describe complex, multi-field parameter structures. The model
below is a truncated Dirichlet process mixture. The type specification is valid and can be
used to create instances and validate shapes; the full model body is shown as an
illustration of the corresponding BUGS program.

```julia
DPMModel = @of(
    n_obs = of(Int, 10, 1000; constant=true),
    n_features = of(Int, 1, 20; constant=true),
    max_clusters = of(Int, 10, 50; constant=true),
    data = of(Array, n_obs, n_features),
    z = of(Array, n_obs),
    v = of(Array, max_clusters - 1),
    weights = of(Array, max_clusters),
    cluster_means = of(Array, max_clusters, n_features),
    cluster_precs = of(Array, max_clusters),
    alpha = of(Real, 0.1, 10.0)
)

@model function dp_mixture(
    (; data, z, v, weights, cluster_means, cluster_precs, alpha)::DPMModel,
    n_obs, n_features, max_clusters
)
    alpha ~ Gamma(1.0, 1.0)
    for k in 1:(max_clusters - 1)
        v[k] ~ Beta(1.0, alpha)
    end
    remaining = 1.0
    for k in 1:max_clusters
        if k < max_clusters
            weights[k] = v[k] * remaining
            remaining *= (1 - v[k])
        else
            weights[k] = remaining
        end
    end
    for k in 1:max_clusters
        cluster_precs[k] ~ Gamma(1.0, 1.0)
        for d in 1:n_features
            cluster_means[k, d] ~ Normal(0.0, 10.0)
        end
    end
    for i in 1:n_obs
        z[i] ~ Categorical(weights)
        for d in 1:n_features
            data[i, d] ~ Normal(
                cluster_means[z[i], d],
                1 / sqrt(cluster_precs[z[i]]),
            )
        end
    end
end
```

!!! note
    The DPM model body above is illustrative of how the `of` type maps to a BUGS program
    structure. It uses conditional logic that is not supported by the current `@model`
    parser and therefore is not executed as part of the documentation build.
