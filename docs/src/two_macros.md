# Two Macros: @bugs and @model

JuliaBUGS provides two macros for defining probabilistic models with different evaluation contexts.

## @bugs

The `@bugs` macro creates model expressions with restricted scope:
- Only has access to BUGS primitives (dnorm, dgamma, exp, log, etc.)
- Custom functions and distributions must be imported using `@bugs_primitive`
- Matches original BUGS language behavior

```julia
# Works - uses only BUGS primitives
model_expr = @bugs begin
    x ~ dnorm(0, 1)
    y = exp(x)
end

# Fails - my_func is not a BUGS primitive
my_func(x) = x + 1
model_expr = @bugs begin
    x ~ dnorm(0, 1)
    y = my_func(x)  # ERROR: UndefVarError
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
