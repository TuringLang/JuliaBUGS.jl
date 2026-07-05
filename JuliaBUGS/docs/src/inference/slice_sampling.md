# Slice Sampling

[SliceSampling.jl](https://github.com/TuringLang/SliceSampling.jl) provides a family of
**derivative-free** slice samplers. Once `using SliceSampling`, they can sample any compiled
`BUGSModel`, so you get gradient-free inference without configuring an AD backend. This is handy
for models with awkward geometry, non-differentiable pieces, or as a robust component sampler
inside `JuliaBUGS.Gibbs`.

Slice samplers are used two ways:

- **Standalone** — pass a slice sampler to `AbstractMCMC.sample` to update the whole model.
- **Inside `JuliaBUGS.Gibbs`** — assign a slice sampler to one or more variable groups in the
  `sampler_map`; JuliaBUGS drives it through the Gibbs sweep.

## Setup

```@example slice
using JuliaBUGS
using JuliaBUGS: Gibbs
using SliceSampling
using AbstractMCMC
using MCMCChains
using OrderedCollections: OrderedDict

model_def = @bugs begin
    mu ~ dnorm(0, 0.0001)
    y ~ dnorm(mu, 1)
end
model = model_def((; y = 1.5))
```

## Standalone sampling

Univariate slice samplers such as `SliceSteppingOut` and `SliceDoublingOut` update one coordinate
at a time. On a single-parameter model you can pass one directly:

```@example slice
chain = AbstractMCMC.sample(
    model,
    SliceSteppingOut(1.0),   # 1.0 is the initial slice window width
    500;
    chain_type = Chains,
    progress = false,
)
summarystats(chain)
```

No `initial_params` is required: the extension implements `SliceSampling.initial_sample`, which
seeds the sampler from the model's current parameter values.

For a model with **more than one parameter**, wrap a univariate sampler in a multivariate
strategy (e.g. `RandPermGibbs`, which cycles through coordinates in a random order), or use a
genuinely multivariate slice sampler:

```@example slice
multi_def = @bugs begin
    a ~ dnorm(0, 1)
    b ~ dnorm(0, 1)
    y ~ dnorm(a + b, 1)
end
multi_model = multi_def((; y = 0.5))

multi_chain = AbstractMCMC.sample(
    multi_model,
    RandPermGibbs(SliceSteppingOut(1.0)),
    500;
    chain_type = Chains,
    progress = false,
)
summarystats(multi_chain)
```

## Inside `Gibbs`

Because each single-site conditional in `JuliaBUGS.Gibbs` is univariate, a bare univariate slice
sampler works per site — no multivariate wrapper needed. Map variable groups to samplers in an
`OrderedDict`:

```@example slice
sampler_map = OrderedDict(
    @varname(a) => SliceSteppingOut(1.0),
    @varname(b) => SliceSteppingOut(1.0),
)
gibbs = Gibbs(multi_model, sampler_map)

gibbs_chain = AbstractMCMC.sample(
    multi_model,
    gibbs,
    500;
    chain_type = Chains,
    progress = false,
)
summarystats(gibbs_chain)
```

Slice samplers can be freely mixed with other samplers (HMC, `IndependentMH`, …) in the same
`sampler_map`.

## Output formats and statistics

Both chain backends are supported:

- `chain_type = Chains` returns an `MCMCChains.Chains` (shown above).
- `chain_type = VNChain` returns a [`FlexiChains.FlexiChain`](https://github.com/penelopeysm/FlexiChains.jl)
  keyed by `VarName` (requires `using FlexiChains`):

```julia
using FlexiChains
chain = AbstractMCMC.sample(model, SliceSteppingOut(1.0), 500; chain_type = VNChain, progress = false)
```

In either case the sampler's own statistics are recorded alongside the draws: the log density
`lp` and `num_proposals` (the number of proposals the slice sampler evaluated per step). Under
`MCMCChains` these appear as `internals`; under `FlexiChains` they are `FlexiChains.Extra`
entries. For a multivariate sampler the per-coordinate `num_proposals` is flattened into
`num_proposals[i]` columns for `MCMCChains`.
