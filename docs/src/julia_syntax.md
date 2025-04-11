# JuliaBUGS Model Syntax

## Legacy Syntax

Previously, JuliaBUGS provided a `@bugs` macro that mirrored the traditional BUGS `compile` interface, accepting model definitions as strings or within a `begin...end` block:

```julia
# Example using string macro (legacy)
@bugs"""
model {
  # Priors for regression coefficients
  beta0 ~ dnorm(0, 0.001)
  beta1 ~ dnorm(0, 0.001)
  # Prior for precision (inverse variance)
  tau ~ dgamma(0.001, 0.001)
  sigma <- 1 / sqrt(tau)
  # Likelihood
  for (i in 1:N) {
    mu[i] <- beta0 + beta1 * x[i]
    y[i] ~ dnorm(mu[i], tau)
  }
}
"""

# Example using block macro (legacy)
@bugs begin
    # Priors for regression coefficients
    beta0 ~ Normal(0, sqrt(1/0.001))
    beta1 ~ Normal(0, sqrt(1/0.001))
    # Prior for precision (inverse variance)
    tau ~ Gamma(0.001, 1/0.001)
    sigma = 1 / sqrt(tau)
    # Likelihood
    for i in 1:N
        mu[i] = beta0 + beta1 * x[i]
        y[i] ~ Normal(mu[i], sqrt(1/tau))
    end
end
```

In both legacy cases, the macro returned a Julia AST representation of the model. The `compile` function then took this AST and user-provided data (as a `NamedTuple`) to create a `BUGSModel` instance. While functional, this approach is less idiomatic in Julia compared to defining models within functions.

In the future, we will only support the first case (using String to define model), and move the latter to a more Julia syntax. (see below)

## `@model` and `@parameters`


### The `@model` Macro

The `@model` macro transforms a standard Julia function definition into a factory for creating `BUGSModel` instances that compatible with `AbstractMCMC.sample` function.

```julia
JuliaBUGS.@model function model_definition((;r, b, alpha0, alpha1, alpha2, alpha12, tau)::MyParams, x1, x2, N, n)
    
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

**Function Signature:**

The `@model` macro expects a specific function signature:

1.  **First Argument (Parameters):** This argument **must** declare the model's stochastic parameters (variables defined using `~`) using destructuring assignment (e.g., `(; param1, param2)`).
    *   **Explicit Declaration:** This explicit declaration of parameters is a design choice. Although JuliaBUGS compiler can determine these variables. We still ask user to specify them to be explicit. 
    *   **Type Annotation (Optional but Recommended):** You can provide a type annotation for the parameters (e.g., `(; r, b, ...)::MyParams`). If you do, and if `MyParams` is defined using `@parameters` (see below), the macro automatically defines a constructor `MyParams(model::BUGSModel)`. This allows easy extraction of fitted parameter values from a `BUGSModel` object back into your structured type.
    *   **`NamedTuple` Alternative:** You can use a `NamedTuple` type annotation or no annotation. However, managing parameter placeholders or default values might require more manual effort compared to using `@parameters`.

2.  **Subsequent Arguments (Constants/Data):** These arguments declare fixed data, constants required by the model logic (e.g., `x1, x2, N, n`). These are variables that used on RHS, but not appeared on the LHS, which are required to compile the model and sample from prior

**Validation:**

The macro performs validation checks:

*   It ensures that all variables read within the function body but *not* assigned via `~` or `=` (i.e., constants or data) are included as arguments *after* the first parameter argument.
*   It verifies that all stochastic parameters (assigned via `~`) are listed in the destructuring assignment of the first argument.

**Model Generation:**

The function created by `@model` acts as a model factory. When you call this function with:

1.  A parameter object (an instance of the struct defined via `@parameters` or a compatible `NamedTuple`).
2.  The required constants/data.

It performs the following steps:

1.  Combines the provided constants and any concrete values from the parameter object into the data structure needed by the BUGS engine.
2.  Parses the model logic defined within the function body.
3.  Calls the internal `JuliaBUGS.compile` function.
4.  Returns a ready-to-use `BUGSModel` object, suitable for sampling with MCMC algorithms (e.g., via `AbstractMCMC.jl`).

### The `@parameters` Macro

The `@parameters` macro simplifies the creation of mutable structs intended to hold model parameters, designed to work seamlessly with `@model`.

```julia
# Example defining a parameter struct
JuliaBUGS.@parameters struct MyParams
    r
    b
    alpha0
    alpha1
    alpha2
    alpha12
    tau
    # sigma is derived, not a parameter defined with ~
end
```

**Features:**

*   **Keyword-Based Construction:** Uses `Base.@kwdef`, allowing easy instantiation with keyword arguments (e.g., `MyParams(alpha0=0.0, tau=1.0)`). If constructed without arguments (e.g., `MyParams()`), fields are initialized with placeholders. Providing initial values can be useful for setting starting points for sampling.
*   **Default Placeholders:** By default, fields are initialized with `JuliaBUGS.ParameterPlaceholder()`. This allows creating parameter struct instances even without initial values, which is necessary during the model compilation phase when only the structure, not the values, might be known. The concrete types and sizes of placeholder parameters are determined during the `compile` step when the model function is called with constants.
*   **Convenient Instantiation from Model:** As mentioned, if a `@parameters` struct is used as the type annotation in `@model`, a constructor `MyParams(model::BUGSModel)` is automatically generated, simplifying the extraction of results post-inference.
*   **Clear Display:** Includes a custom `Base.show` method that indicates whether fields hold concrete values or placeholders, aiding inspection and debugging.

