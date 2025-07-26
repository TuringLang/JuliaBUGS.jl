
- **`@bugs` macro**: Provides strict BUGS compatibility with automatic imports
- **`@model` macro**: Follows Julia conventions with explicit imports

## The `@bugs` Macro (Legacy)

The `@bugs` macro is designed for users migrating from BUGS/JAGS/Stan or those who prefer the classic BUGS syntax.

### Features
- **Automatic imports**: All BUGS functions and distributions are automatically available
- **Strict validation**: Only whitelisted functions are allowed by default
- **Legacy syntax support**: Write models exactly as you would in BUGS

### Whitelisted Functions
The following are automatically available without any imports:

#### BUGS Distributions
- `dnorm`, `dbin`, `dpois`, `dexp`, `dgamma`, `dbeta`, `dunif`, etc.
- Both BUGS-style (`dnorm(0, 1)`) and Julia-style (`Normal(0, 1)`) syntax

#### Mathematical Functions
- Basic: `abs`, `exp`, `log`, `sqrt`, `sin`, `cos`, `tan`
- Statistical: `mean`, `sum`, `prod`, `min`, `max`
- Special: `logit`, `probit`, `cloglog`, `phi`

### Example Usage

```julia
# No imports needed!
model = @bugs begin
    # Priors
    mu ~ dnorm(0, 0.001)
    tau ~ dgamma(0.01, 0.01)
    sigma <- 1/sqrt(tau)
    
    # Likelihood
    for i in 1:N
        y[i] ~ dnorm(mu, tau)
    end
end
```

### Using Non-Whitelisted Functions

Use `@bugs_primitive` to register

## The `@model` Macro (Julia Convention)

The `@model` macro follows standard Julia conventions, giving you full control over your namespace.

### Features
- **Explicit imports**: You control what's available in your model
- **Module respect**: Uses your current module's context
- **Julia integration**: Seamlessly use any Julia package

### Required Imports

Unlike `@bugs`, you must explicitly import what you need:

```julia
# For BUGS-style distributions
using JuliaBUGS.BUGSPrimitives

# For Julia distributions
using Distributions

# For other packages
using LinearAlgebra, SpecialFunctions
```

### Example Usage

```julia
using JuliaBUGS.BUGSPrimitives
using Distributions
using LinearAlgebra

model = @model begin
    # Can use both BUGS and Julia syntax
    mu ~ Normal(0, 10)  # Julia style
    tau ~ dgamma(0.01, 0.01)  # BUGS style
    
    # Access to imported packages
    Σ = I(2) * tau  # From LinearAlgebra
    
    for i in 1:N
        y[i] ~ MvNormal(μ, Σ)
    end
end
```

### Qualified Names

The `@model` macro fully supports Julia's qualified names:

```julia
using Distributions

model = @model begin
    # Fully qualified
    x ~ Distributions.Normal(0, 1)
    
    # Can also use custom packages without importing
    y <- MyPackage.transform(x)
end
```
