# Sampling Output Formats

`AbstractMCMC.sample` builds its result from the `chain_type` keyword. JuliaBUGS supports three
formats, all carrying the same draws: the model parameters, the forward-sampled generated
quantities, and the sampler's own statistics.

```@example output
using JuliaBUGS
using AbstractMCMC
using MCMCChains

model_def = @bugs begin
    mu ~ dnorm(0, 1)
    for i in 1:N
        y[i] ~ dnorm(mu, 1)
    end
    doubled = 2 * mu
end
model = model_def((; N = 3, y = [1.2, 0.8, 1.5]))
```

## `Vector{ParamsWithStats}`

`chain_type = Vector{ParamsWithStats}` returns one
[`AbstractMCMC.ParamsWithStats`](https://turinglang.org/AbstractMCMC.jl/stable/callbacks/#ParamsWithStats)
per draw. It is the most general of the three and the only one that needs no extra package,
since `AbstractMCMC` is already a dependency. It is not the most compact: a chain stores one
array, whereas this repeats the `VarName` keys for every draw.

```@example output
draws = AbstractMCMC.sample(
    model,
    JuliaBUGS.IndependentMH(),
    500;
    chain_type = Vector{ParamsWithStats},
    progress = false,
)
draws[1]
```

Each entry has two fields. `params` is an `OrderedDict` keyed by `VarName`, so array-valued
variables are stored whole rather than split into scalar columns:

```@example output
draws[1].params[@varname(mu)]
```

`stats` is a `NamedTuple` of the statistics the sampler reported for that draw. Only what the
sampler actually produced is recorded, so a statistic missing from one draw is absent from its
`NamedTuple` rather than padded. `Base.pairs` walks parameters and statistics at once:

```@example output
using AdvancedHMC, ADTypes, ReverseDiff, DifferentiationInterface

ad_model = compile(model_def, (; N = 3, y = [1.2, 0.8, 1.5]); adtype = AutoReverseDiff())
nuts_draws = AbstractMCMC.sample(
    ad_model,
    NUTS(0.8),
    200;
    chain_type = Vector{ParamsWithStats},
    n_adapts = 100,
    discard_initial = 100,
    progress = false,
)
collect(Base.pairs(nuts_draws[1]))
```

A plain vector carries no iteration indices, so `discard_initial` and `thinning` are not
recorded in it. Pass them back when converting (see below) if you need the chain to report the
iteration numbers the run actually used.

Multiple chains come back as one vector per chain:

```julia
chains = AbstractMCMC.sample(
    model, JuliaBUGS.IndependentMH(), MCMCThreads(), 500, 4;
    chain_type = Vector{ParamsWithStats},
)
length(chains)     # 4
length(chains[1])  # 500
```

## `MCMCChains.Chains`

`chain_type = Chains` returns an `MCMCChains.Chains` (requires `using MCMCChains`). Array-valued
variables and statistics are flattened into one scalar column per element, and the statistics go
into the `internals` section.

## `FlexiChains.VNChain`

`chain_type = VNChain` returns a
[`FlexiChains.FlexiChain{VarName}`](https://github.com/penelopeysm/FlexiChains.jl) (requires
`using FlexiChains`). Draws are keyed by `VarName` with array-valued variables kept whole, and
statistics are stored as `FlexiChains.Extra` entries.

## Converting between formats

A vector of `ParamsWithStats` converts into either chain type with
`AbstractMCMC.from_samples`. It takes a matrix of draws, iterations down the rows and chains
across the columns, so a single run needs a `reshape`:

```@example output
chain = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))
summarystats(chain)
```

`start` and `thin` restore the iteration numbering a run used, since the vector does not carry
it: for `discard_initial = n` pass `start = n + 1`.

```julia
chain = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1); start = 101, thin = 2)
```

Several chains go in as columns:

```julia
chain = AbstractMCMC.from_samples(Chains, reduce(hcat, chains))
```

```julia
using FlexiChains
chain = AbstractMCMC.from_samples(VNChain, reshape(draws, :, 1))
```

For [ArviZ.jl](https://julia.arviz.org), go through `VNChain`: FlexiChains ships an
InferenceObjects extension that keeps array-valued variables whole and maps the HMC statistic
names onto ArviZ's conventions (`hamiltonian_energy` to `energy`, `numerical_error` to
`diverging`). Converting via `Chains` works too but flattens arrays into `x[1]`, `x[2]` and
loses that mapping.

## Reproducing generated quantities

Generated quantities are forward-sampled when the draws are laid out, using the global RNG
rather than the sampler's. Pass `rng` to `sample` to make stochastic generated quantities
reproducible:

```julia
draws = AbstractMCMC.sample(
    model, JuliaBUGS.IndependentMH(), 500;
    chain_type = Vector{ParamsWithStats}, rng = StableRNG(1),
)
```

## What a callback sees

`AbstractMCMC.ParamsWithStats(model, sampler, transition, state)` inside an `mcmc_callback`
reports the same `VarName`-keyed parameters and the same sampler statistics, for every
sampler. It does **not** include generated quantities: those are forward-sampled once at the
end of a run, so they appear only in the sampling output.

## Supporting a new sampler

A sampler works with all three formats once it implements a single method that unpacks its
transitions:

```julia
function JuliaBUGS.transition_params_and_stats(::BUGSModel, ::MySampler, t::MyTransition)
    return t.params, (; lp = t.lp)
end
```

`params` is the flat parameter vector for that draw, ordered as
`LogDensityProblems.logdensity` expects it, and `stats` is whatever the sampler reported.
Report only what it actually produced: leave a statistic out of the `NamedTuple` rather than
padding it, and array-valued statistics are fine. `Chains` takes the union of the keys across
draws and flattens arrays itself.

This one method also drives what a callback sees, so implementing it is enough for every
output format.
