# Initial Values

JuliaBUGS draws initial values from each parameter's prior when it constructs a model. This is
often sufficient, but explicit initial values are useful when reproducing an existing BUGS
analysis, comparing chains from known starting points, or working with priors that can generate
poor starting values.

## Initialize while constructing a model

Pass a `NamedTuple` of initial values as the second argument when calling an `@bugs` model
definition:

```@example initialization
using JuliaBUGS

model_def = @bugs begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    y ~ dnorm(b, 1)
end

data = (; y=3.0)
inits = (; a=1.0, b=2.0)
model = model_def(data, inits)
nothing # hide
```

The names in `inits` correspond to unobserved stochastic variables in the model. Named values are
given in the variables' original, constrained space.

Initial values can be partial. JuliaBUGS draws omitted parameters from their priors and then
recomputes deterministic variables:

```@example initialization
model = model_def(data, (; a=1.0))
nothing # hide
```

Array-valued parameters are initialized under their model name with an array of the corresponding
shape. For example, a model containing `theta[i] ~ dnorm(0, 1)` for `i in 1:3` accepts
`(; theta=[1.0, 2.0, 3.0])`.

## Reinitialize an existing model

Use `initialize!` to replace the initial state after constructing a model:

```@example initialization
model = model_def(data)
model = initialize!(model, inits)
nothing # hide
```

As during construction, a `NamedTuple` contains values in the original space and may omit
parameters that should be drawn from their priors.

`initialize!` also accepts a flat parameter vector. Its order must match the model's parameter
order, and its values use transformed coordinates when the model is in transformed mode. A safe
way to obtain a compatible vector is to start from the model's current parameters:

```julia
initial_θ = JuliaBUGS.getparams(model)
model = initialize!(model, initial_θ)
```

## Initial values passed to a sampler

Samplers using the `AbstractMCMC` interface accept a flat parameter vector through `init_params`:

```julia
initial_θ = JuliaBUGS.getparams(model)
chain = AbstractMCMC.sample(
    model, sampler, n_samples;
    init_params=initial_θ,
    # other sampler options...
)
```

For multiple chains, provide one initial vector per chain. See
[Parallel and Distributed Sampling](../inference/parallel.md) for the multi-chain forms.

The classic examples bundled with JuliaBUGS include published initial values. For example,
`JuliaBUGS.BUGSExamples.VOLUME_1.seeds.inits` is a `NamedTuple` that can be passed while
constructing or reinitializing the Seeds model.
