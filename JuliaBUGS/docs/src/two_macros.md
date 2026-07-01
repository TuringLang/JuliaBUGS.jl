# Two Macros: @bugs and @model

JuliaBUGS provides two macros for defining probabilistic models. With both, you go from a model
definition to a `BUGSModel` by *calling* the definition with your data. They differ in the input
syntax they accept, in how the definition is called, and in their function-access policy.

## @bugs

The `@bugs` macro builds a model definition from BUGS-language syntax. It returns a callable
[`BUGSModelDef`](@ref JuliaBUGS.BUGSModelDef); calling it with data constructs a `BUGSModel`.

- Only BUGS primitives (dnorm, dgamma, exp, log, etc.) are available
- Custom functions must be registered using `@bugs_primitive`
- Qualified function names (e.g., `Base.exp`, `Distributions.Normal`) are not allowed

```julia
# Works - uses only BUGS primitives
transformed_model = @bugs begin
    x ~ dnorm(0, 1)
    y = exp(x)
end

model = transformed_model((; x = 1.5))  # construct a BUGSModel

# To use custom functions, register them first:
my_func(x) = x + 1
@bugs_primitive my_func

transformed_model = @bugs begin
    x ~ dnorm(0, 1)
    y = my_func(x)  # Now works!
end
```

## @model

The `@model` macro defines a model-generating *function* with full Julia scope. Instead of a
`BUGSModelDef`, it introduces a named function; call that function with the observations/parameters
(a `NamedTuple`) plus any constants to construct a `BUGSModel`.

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

model = my_model((; theta = 0.5))  # construct a BUGSModel
```
