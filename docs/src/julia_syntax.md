# How to Specify and Create a `BUGSModel`

It takes a BUGS program and the values of some variables to specify a BUGS model.
Before we move on, it is instructional to explain and distinguish between different kinds of values one can give to the JuliaBUGS compiler.
* constants: values used in loop bounds, variables used to resolve indices
    * these values are required to specify the model, the former decides the size of the model (how many variables) and the latter is part of the process of determine the edges
* independent variables (features, predictors, covariances): these are variables required for forward simulation of the model
* observations: values of stochastic variables, these are not necessary to specify the model, but if there are provided, they will be data that the conditioned model is conditioned on. (exception is that, one can use stochastic variables to add to the log density, but this is not strictly generative modeling).
* initialization: these are points for the MCMC to start, some models, for instance poorly specified models or model with wide priors might require carefully picked initialization values to run. 

## Syntax from previous BUGS softwares and their R packages

Previously, users ues BUGS language through the software interface. Which on a high level, comprised of following steps:
1. write the model in a text file
2. check the model (parsing)
3. compile the model with the program text and data
4. (optional) initialize the sampling process

Because the R interface packages rely on the BUGS softwares, their interface, albeit in a pure text-based (R program) interface, closely mimic the software interfaces.

Until now, JuliaBUGS has inherent this interface. Partially because the interface is intuitive enough, and we want to provide users with previous BUGS experience a familiar interface. To be explicit, JuliaBUGS provided a `@bugs` macro that accepts model definitions as strings or within a `begin...end` block:

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

In both cases, the macro returned a Julia AST representation of the model. The `compile` function then took this AST and user-provided values (as a `NamedTuple`) to create a `BUGSModel` instance.

We still want to preserve this interface for users with previous BUGS experiences. But at the same time, we also want to provide an interface that's more idiomatic in Julia.

## The interface

We take heavy inspiration from Turing.jl's model macro syntax.
The `model` macro creates a "model creating function", which takes some input and returns a model upon which many operations are defined.
The operations includes `AbstractMCMC.sample` and functions like `condition`.

### The `@model` Macro

```julia
JuliaBUGS.@model function model_definition((;r, b, alpha0, alpha1, alpha2, alpha12, tau)::Params, x1, x2, N, n)    
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

The `model` macro expects a specific function signature:

The first argument **must** declare the model's stochastic parameters (variables defined using `~`) using destructuring assignment (e.g., `(; param1, param2)`).
all stochastic parameters (assigned via `~`) are listed in the destructuring assignment of the first argument.
We encourage users to provide a type annotation for the parameters (e.g., `(; r, b, ...)::Params`). 
If you do, and if `Params` is defined using `@parameters` (see below), the macro automatically defines a constructor `MyParams(model::BUGSModel)`. This allows easy extraction of fitted parameter values from a `BUGSModel` object back into your structured type.
It is also possible to use a `NamedTuple` type annotation or no annotation. 
However, user would need to create the NamedTuple with `ParameterPlaceholder` or Array (possibly of `missing`s), instead of the automatically generated constructors (see below).  

The rest of the arguments need to give all the constants and independent variables required by the model logic (e.g., `x1, x2, N, n`). These are variables that used on RHS, but not appeared on the LHS, which are required to compile the model and sample from prior.

Like mentioned before, The `@parameters` macro simplifies the creation of mutable structs intended to hold model parameters, designed to work seamlessly with `@model`.

```julia
JuliaBUGS.@parameters struct Params
    r
    b
    alpha0
    alpha1
    alpha2
    alpha12
    tau
end
```

The macro is simple -- it `Base.@kwdef` to allowing easy instantiation with keyword arguments. particularly, it creates a constructor that takes no argument. 
In this case, all the field will be default to `JuliaBUGS.ParameterPlaceholder`.
Alternatively, one can also use Arrays of `missing`s if the variable is not observation.
The concrete types and sizes of placeholder parameters are determined during the `compile` step when the model function is called with constants.
A cosntructor `Params(::BUGSModel)` is created.

### Example

```julia
julia> @model function seeds(
        (; r, b, alpha0, alpha1, alpha2, alpha12, tau)::Params, x1, x2, N, n
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

julia> @parameters struct Params
        r
        b
        alpha0
        alpha1
        alpha2
        alpha12
        tau
    end

julia> m = seeds(Params(), x1, x2, N, n)
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

julia> Params(m)
Params:
  r       = [0.0, 0.0, 0.0, 0.0, 39.0, 0.0, 0.0, 72.0, 0.0, 0.0  …  0.0, 0.0, 0.0, 0.0, 4.0, 12.0, 0.0, 0.0, 0.0, 0.0]
  b       = [-Inf, -Inf, -Inf, -Inf, Inf, -Inf, -Inf, Inf, -Inf, -Inf  …  -Inf, -Inf, -Inf, -Inf, Inf, Inf, -Inf, -Inf, -Inf, -Inf]
  alpha0  = -1423.52
  alpha1  = 1981.99
  alpha2  = -545.664
  alpha12 = 1338.25
  tau     = 0.0
```
