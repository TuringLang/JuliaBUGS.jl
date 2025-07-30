# Two Macros: @bugs and @model

JuliaBUGS provides two macros for defining probabilistic models with different function access policies.

## @bugs

The `@bugs` macro creates model expressions compatible with the BUGS language:
- Only BUGS primitives (dnorm, dgamma, exp, log, etc.) are available
- Custom functions must be registered using `@bugs_primitive`
- Qualified function names (e.g., `Base.exp`, `Distributions.Normal`) are not allowed

```julia
# Works - uses only BUGS primitives
model_expr = @bugs begin
    x ~ dnorm(0, 1)
    y = exp(x)
end

# To use custom functions, register them first:
my_func(x) = x + 1
@bugs_primitive my_func

model_expr = @bugs begin
    x ~ dnorm(0, 1)
    y = my_func(x)  # Now works!
end
```

## @model

The `@model` macro creates model-generating functions with full Julia scope:
- Has access to all imports and functions in the calling module
- Requires explicit imports of BUGS primitives
- More flexible for Julia integration

```julia
using JuliaBUGS.BUGSPrimitives: dnorm

my_transform(x) = x^2 + 1

@model function my_model((; theta))
    theta ~ dnorm(0, 1)
    y = my_transform(theta)  # Works - has access to user functions
end
```
