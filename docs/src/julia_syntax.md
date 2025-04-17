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

```julia
JuliaBUGS.@model function model_definition((;r, b, alpha0, alpha1, alpha2, alpha12, tau)::SeedsParams, x1, x2, N, n)    
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

The `@model` macro requires a specific function signature:

1. The first argument must declare stochastic parameters (variables defined with `~`) using destructuring assignment with the format `(; param1, param2, ...)`.
2. We recommend providing a type annotation (e.g., `(; r, b, ...)::SeedsParams`). If `SeedsParams` is defined using `@parameters`, the macro automatically defines a constructor `SeedsParams(model::BUGSModel)` for extracting parameter values from the model.
3. Alternatively, you can use a `NamedTuple` instead of a custom type. In this case, no type annotation is needed, but you would need to manually create a `NamedTuple` with `ParameterPlaceholder()` values or arrays of `missing` values for parameters that don't have observations.
4. The remaining arguments must specify all constants and independent variables required by the model (variables used on the RHS but not on the LHS).

The `@parameters` macro simplifies creating structs to hold model parameters:

```julia
JuliaBUGS.@parameters struct SeedsParams
    r
    b
    alpha0
    alpha1
    alpha2
    alpha12
    tau
end
```

This macro applies `Base.@kwdef` to enable keyword initialization and creates a no-argument constructor. By default, fields are initialized to `JuliaBUGS.ParameterPlaceholder`. The concrete types and sizes of parameters are determined during compilation when the model function is called with constants. A constructor `SeedsParams(::BUGSModel)` is created for easy extraction of parameter values.

### Example

```julia
julia> @model function seeds(
        (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::SeedsParams, x1, x2, N, n
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

julia> @parameters struct SeedsParams
        r
        b
        alpha0
        alpha1
        alpha2
        alpha12
        tau
    end

julia> m = seeds(SeedsParams(), x1, x2, N, n)
BUGSModel (parameters are in transformed (unconstrained) space, with dimension 47):

  Model parameters:
    alpha2
    b[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1]
    r[21], r[20], r[19], r[18], r[17], r[16], r[15], r[14], r[13], r[12], r[11], r[10], r[9], r[8], r[7], r[6], r[5], r[4], r[3], r[2], r[1]
    tau
    alpha12
    alpha1
    alpha0

  Variable sizes and types:
    b: size = (21,), type = Vector{Float64}
    p: size = (21,), type = Vector{Float64}
    n: size = (21,), type = Vector{Int64}
    alpha2: type = Float64
    sigma: type = Float64
    alpha12: type = Float64
    alpha0: type = Float64
    N: type = Int64
    tau: type = Float64
    alpha1: type = Float64
    r: size = (21,), type = Vector{Float64}
    x1: size = (21,), type = Vector{Int64}
    x2: size = (21,), type = Vector{Int64}

julia> SeedsParams(m)
SeedsParams:
  r       = [0.0, 0.0, 0.0, 0.0, 39.0, 0.0, 0.0, 72.0, 0.0, 0.0  …  0.0, 0.0, 0.0, 0.0, 4.0, 12.0, 0.0, 0.0, 0.0, 0.0]
  b       = [-Inf, -Inf, -Inf, -Inf, Inf, -Inf, -Inf, Inf, -Inf, -Inf  …  -Inf, -Inf, -Inf, -Inf, Inf, Inf, -Inf, -Inf, -Inf, -Inf]
  alpha0  = -1423.52
  alpha1  = 1981.99
  alpha2  = -545.664
  alpha12 = 1338.25
  tau     = 0.0
```
