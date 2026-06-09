# Model as a Distribution

`to_distribution` wraps a compiled `BUGSModel` as a
`Distributions.Distribution` whose variate is a `NamedTuple`. This lets you
treat a model's joint density as an ordinary distribution object: you can `rand`
a draw and evaluate `logpdf` / `pdf` / `loglikelihood` on a `NamedTuple` keyed by
the model's parameter symbols.

The wrapper is deliberately a *constrained-space* view of the model. It always
evaluates in the model's original parameter space, always uses graph evaluation,
and `logpdf` returns the **full joint** density (prior plus the likelihood of any
observed data baked into the model). It is **not** an unconstrained-space target
for gradient-based samplers — see the [Limitations](#Limitations-and-non-goals)
admonition below.

You obtain a `BUGSModel` by compiling a model definition with `compile`
(see [Getting Started](example.md) and
[Two Macros: `@bugs` & `@model`](two_macros.md)), then pass it to
`to_distribution`.

## Quick Example

```@example modeldist
using JuliaBUGS, Distributions, Random
Random.seed!(123)  # make the draw below reproducible

model_def = @bugs begin
    x ~ dnorm(0, 1)
    y ~ dnorm(x, 1)
end

# `y` is observed data; `x` is the only free parameter.
model = compile(model_def, (; y = 1.0))
d = to_distribution(model)
```

A draw is a `NamedTuple` keyed by the parameter symbol:

```@example modeldist
nt = rand(d)
```

`logpdf` returns the log joint density:

```@example modeldist
logpdf(d, nt)   # logprior(x) + loglikelihood(y | x)
```

`pdf` is its exponential, and `loglikelihood` is an alias for the *same* joint
(not a data-only likelihood) — so it equals `logpdf`:

```@example modeldist
pdf(d, nt), loglikelihood(d, nt) == logpdf(d, nt)
```

`rand(d)` performs ancestral sampling and returns one `NamedTuple` field per
unique parameter symbol; `logpdf(d, nt)` accepts the same shape and returns the
log joint density in the model's original (constrained) parameter space.

## Interface Reference

### The variate type

`to_distribution(model)` returns a
`BUGSModelDistribution{names,M,S,T} <: Distribution{NamedTupleVariate{names},S}`.
The variate is a `NamedTuple` whose fields are the **unique top-level parameter
symbols** of the model. The keys are derived by iterating `parameters(model)`,
taking `AbstractPPL.getsym(vn)` for each parameter `VarName`, and deduplicating
while preserving graph evaluation order.

There is exactly one field per top-level symbol. An array parameter is therefore
a single whole-array field (e.g. `(x = [v1, v2, v3],)`) — never one key per
element. A `NamedTuple`'s field names must be plain `Symbol`s, so indexed names
like `Symbol("x[1]")` are not used (and would not resolve as `@varname(x[1])`).

### Type parameters

| Param   | Meaning |
|---------|---------|
| `names` | Tuple of `Symbol`s — the unique parameter symbols, from `getsym` over `parameters(model)` in graph evaluation order, duplicates removed. These are the `NamedTuple` keys. |
| `M`     | `M <: BUGSModel` — the concrete type of the wrapped model. The struct has a single field `model::M`. |
| `S`     | `S <: Distributions.ValueSupport` — computed over the **free** (stochastic, unobserved) nodes by `promote_type` of each node's `value_support`. Defaults to `Continuous` when there are no free stochastic nodes; mixed discrete/continuous promotes to `Continuous`. |
| `T`     | The `NamedTuple` eltype `NamedTuple{names,Tuple{Ts...}}`, where each `Ts[i]` is the concrete type of `getfield(model.evaluation_env, names[i])` (e.g. a full array type). Returned by `eltype(d)` and used to allocate the array in the `dims`-form `rand`. |

### Sampling and density methods

| Method | Behavior |
|--------|----------|
| `rand(rng, d)` | Ancestral sampling via `evaluate_with_rng!!(rng, model; transformed=false)`; returns a `NamedTuple{names}` reading each symbol from the resulting evaluation environment by `getfield`. |
| `rand(rng, d, dims::Dims)` | Allocates `Array{eltype(d)}(undef, dims)` and fills each element with a scalar `rand(rng, d)`. This explicit form exists because `Random.rand` has no built-in array fallback for `Distribution{NamedTupleVariate}` (without it the call would recurse to a `StackOverflowError`). |
| `Distributions._rand!(rng, d, xs)` | Fills `xs` in place with scalar draws over `eachindex(xs)`. No shape validation beyond `eachindex`. |
| `logpdf(d, x::NamedTuple)` | Returns the full joint `logprior + loglikelihood` in constrained space (no Jacobian). Reads only free parameters from `x`; throws `ArgumentError` for a missing free parameter. |
| `pdf(d, x::NamedTuple)` | `exp(logpdf(d, x))`. |
| `loglikelihood(d, x::NamedTuple)` | Direct alias for `logpdf(d, x)` — the full joint, **not** a data-only likelihood. |
| `loglikelihood(d, xs::AbstractArray{<:NamedTuple})` | `sum` of per-sample joint `logpdf`s with `init=0.0` (treats samples as iid; empty array gives `0.0`). |
| `eltype(d)` | The type parameter `T` (the `NamedTuple` eltype). |
| `show(io, d)` | Prints `BUGSModelDistribution{<names>}(…)`; does not print the wrapped model. |

`logpdf` (and thus `pdf` / `loglikelihood`) throws

```
ArgumentError: logpdf: missing value for parameter `$vn` in NamedTuple input
```

when `AbstractPPL.hasvalue(x, vn)` is false for any free-parameter `VarName`.

## Semantics

### `rand` bakes observed data into whole arrays

`rand(rng, d)` runs ancestral sampling and then reads each parameter symbol back
out of the evaluation environment with `getfield`. Because it reads the whole
top-level symbol, for a partially-observed array the returned field is the
**full array** — free slots filled by the sampled values, observed slots holding
the model's baked-in data. The draw is therefore ready to be fed straight back
into `logpdf`.

### `logpdf` reads only the free parameters

`logpdf` starts from an isolated copy of the model's evaluation environment
(`smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)`, *not*
the live env, to avoid mutating the model's deterministic array nodes), which
already contains the observed data. It then overlays **only the free
parameters**: for each `vn in parameters(model)` it reads the value from `x` by
that `VarName`'s optic (`AbstractPPL.getvalue`) and writes it with
`BangBang.setindex!!(env, value, vn)`. Observed data (already in `env`) and
deterministic nodes (recomputed during evaluation) are never read from `x`.

A direct consequence: `logpdf` is **invariant** to whatever you place in observed
or deterministic slots of the input. For a partially-observed array, only the
free-parameter slots affect the result; the observed slots are ignored and the
model's own data is scored instead.

```@example modeldist_partial
using JuliaBUGS, Distributions

model_def = @bugs begin
    for i in 1:3
        x[i] ~ dnorm(0, 1)
    end
end

# x[1] observed, x[2] and x[3] free.
model = compile(model_def, (; x = [1.0, missing, missing]))
d = to_distribution(model)

# Pass a full-shaped array. The first slot's value is ignored — the model's
# observed x[1] = 1.0 is scored regardless of what you put there:
logpdf(d, (x = [999.0, 0.5, -0.5],)) == logpdf(d, (x = [1.0, 0.5, -0.5],))
```

The cleanest usage is to start from a `rand(d)` draw and modify only the
free positions before calling `logpdf`.

!!! warning "Scoring different data requires a new model"
    Tweaking an observed or deterministic slot is **inert** — the observed data
    is part of the distribution's *identity*. To evaluate the density under
    *different* observed data, `compile` a new model and call `to_distribution`
    again; you cannot do it by changing the values you pass to `logpdf`. This
    matches DynamicPPL's `logjoint` / `loglikelihood(model, params)`, which take
    observed values from the model, not from `params`. (This is also why a value
    passed for a *deterministic* node is discarded: such a node is a function of
    the parameters and is always recomputed.)

### Constrained space, no Jacobian

Both `rand` and `logpdf` force `transformed=false`, regardless of
`model.transformed`. `logpdf` adds **no log-abs-det-Jacobian**: it returns a
density with respect to the natural (constrained) variate the user supplies and
receives. This makes the wrapper a faithful density over the `NamedTuple` it
accepts, but means it is not, on its own, a correct unconstrained-space target.

### Full joint density

`logpdf` returns the untempered joint `log_densities.logprior +
log_densities.loglikelihood` (independent of any temperature default), with
observed data baked into the model. Two models that differ only in their observed
data are different `BUGSModelDistribution`s and give different `logpdf` values for
the same free-parameter input. `loglikelihood(d, x::NamedTuple)` is an alias for
this joint `logpdf` — it is *not* a prior-only or data-only quantity. Use the
underlying model API if you need those terms separately.

### Value support reduction

The `S` type parameter is computed by collecting the `value_support` of every
free (stochastic, unobserved) node's distribution and reducing with
`promote_type`. A model whose free parameters mix discrete and continuous
distributions therefore reports `Continuous`; a model with no free stochastic
nodes defaults to `Continuous`. This reported support is lossy and is cosmetic
for density evaluation — each node still uses its true distribution — but generic
code dispatching on `value_support(typeof(d))` should be aware of the collapse.

### Always graph evaluation; `evaluation_mode` warning

The wrapper always uses graph evaluation (`UseGraph`) and ignores
`model.evaluation_mode`. If the model's mode is not a `UseGraph`,
`to_distribution` emits a one-time (`maxlog=1`) `@warn` noting that it ignores
the mode and that its `logpdf` may differ from `LogDensityProblems.logdensity`
for such a model (e.g. a marginalized one). See [Evaluation Modes](inference/evaluation_modes.md)
and [Auto-Marginalization](inference/auto_marginalization.md) for the modes this
concerns.

## Design notes / decisions

### Symbol-grouped `NamedTuple` variate

The variate keys are top-level symbols, not per-element optics. A `NamedTuple`'s
fields must be plain `Symbol`s, so they can only carry top-level identifiers;
`getsym` is exactly the function that maps a `VarName` back to its top-level
symbol, and deduplicating with a membership check (rather than a `Set`) keeps a
stable, reproducible field ordering tied to graph evaluation order.

The tradeoff is intrinsic to choosing a `NamedTuple` variate: it cannot
distinguish a loop-declared array `x[i]` from a single multivariate node
`x[1:3]` (both become `(x = Vector,)`), and it cannot key individual array
elements. Callers needing per-element addressing must use a different container
(a `Dict{VarName}` or a `VarNamedTuple` with real `VarName` keys), which is
outside this interface.

### Observed data sourced from the model

`logpdf` overlays only free parameters by their precise `VarName` optic and
leaves observed and deterministic entries to the model. An earlier implementation
overlaid whole top-level symbols by bare `Symbol`
(`setindex!!(env, x.x, :x)`), which clobbered the observed slots of a
partially-observed array with caller-supplied values — making the density depend
on junk in observed positions. Addressing each free parameter by `VarName`
touches exactly the stochastic-unobserved slots; using `smart_copy` rather than
the live env keeps `logpdf` free of observable side effects on the model's
deterministic array nodes.

### Consistency with DynamicPPL

This design intentionally mirrors DynamicPPL's `NamedTuple` draw / `logjoint`
path:

- **Symbol-grouped keys.** In DynamicPPL, `NamedTuple(rand(model))` yields one
  field per top-level symbol with arrays reconstructed, e.g. `(x = [v1,v2,v3],)`;
  a loop-declared array and a single multivariate node are indistinguishable in
  that representation. JuliaBUGS uses the same `getsym`-derived symbol keys.
- **Per-element names live only in the chains layer.** Indexed names like `x[1]`,
  `X[1,1]` exist only in DynamicPPL's MCMCChains / sample-table layer
  (`Symbol(string(vn))`), never in the `NamedTuple` draw / `logjoint` layer — a
  field literally named `Symbol("x[1]")` does not resolve as `@varname(x[1])`.
  JuliaBUGS's variate is the draw/`logpdf` layer, so it is likewise symbol-grouped.
- **Observed data comes from the model.** DynamicPPL's
  `logjoint`/`logprior`/`loglikelihood(model, params)` source observed/conditioned
  values from the **model**, not from `params`: changing values in observed slots
  does not change the result, and a missing free parameter errors.
  `logpdf(d, nt)` is the direct analog of `logjoint(model, nt)`, with the same
  constrained-space, no-Jacobian semantics.

### Full-joint semantics and the `loglikelihood` alias

Because observed data is part of the model rather than the variate, the natural
density over the free-parameter `NamedTuple` is the joint (prior times the
likelihood of the baked-in data). Defining `Distributions.loglikelihood` as an
alias for the joint `logpdf` populates the Distributions interface without
inventing a separate, ambiguous data-only quantity the wrapper cannot cleanly
express. This is a naming divergence from DynamicPPL, which keeps `logprior`,
`loglikelihood`, and `logjoint` as distinct functions.

### Always `UseGraph`

Graph evaluation is the well-defined path for ancestral sampling and for
overlaying free parameters by `VarName`, giving a consistent, predictable joint
density. Other modes (e.g. marginalization) compute a different quantity, so the
wrapper fixes the mode rather than silently producing a number whose meaning
depends on a mode the caller may not be tracking; the rate-limited warning
informs without spamming. For a marginalized model, `logpdf(d, nt)` can disagree
with `LogDensityProblems.logdensity(model, ...)` — the warning flags this, but
the divergence is real.

### Partially-observed arrays

A symbol-grouped variate forces one field per array, so the contract is: pass a
full-shaped array (exactly what `rand(d)` returns), and the wrapper extracts only
the free-parameter slots it actually needs. This makes `rand`/`logpdf`
round-trip cleanly while remaining invariant to observed-slot contents. The
surprise is that some supplied entries are silently ignored; the cleanest usage
is to modify a `rand(d)` draw in place.

## Limitations and non-goals

!!! warning
    - **Not an unconstrained-space / HMC target.** The wrapper ignores
      `model.transformed` and adds **no log-abs-det-Jacobian** (constrained-space
      density). Handing it to a gradient-based unconstrained sampler would sample
      the wrong distribution for any constrained parameter. Use the model's
      `LogDensityProblems` interface (linked) for an HMC/NUTS target instead.
    - **`logpdf` is the full joint, not a likelihood.** `loglikelihood(d, x)` is
      an alias for the joint `logpdf` (prior plus likelihood of baked-in data),
      not a data-only likelihood.
    - **Always `UseGraph`.** `model.evaluation_mode` is ignored; for a
      marginalized model `logpdf` can differ from
      `LogDensityProblems.logdensity`.
    - **Observed/deterministic input slots are ignored.** Only free-parameter
      slots are read from the input `NamedTuple`. Partially-observed arrays must
      be passed full-shaped (as `rand` returns); their observed slots are inert.
    - **Mixed support collapses to `Continuous`.** A model mixing discrete and
      continuous free parameters reports `Continuous` for its `ValueSupport`.

## API

```@docs
to_distribution
```
