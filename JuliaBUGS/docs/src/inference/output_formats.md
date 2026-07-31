# Sampling Output Formats

`AbstractMCMC.sample` builds its result from the `chain_type` keyword. JuliaBUGS supports three
formats, all carrying the same draws: the model parameters, the forward-sampled generated
quantities, and the sampler's own statistics.

```@example output
using JuliaBUGS
using AbstractMCMC

model_def = @bugs begin
    mu ~ dnorm(0, 0.0001)
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
per draw. This is the lightest format and the only one that needs no extra package, since
`AbstractMCMC` is already a dependency.

```@example output
draws = AbstractMCMC.sample(
    model,
    JuliaBUGS.IndependentMH(),
    100;
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

`stats` is a `NamedTuple` of the sampler's per-iteration statistics, empty for samplers that
report none. `Base.pairs` walks both at once:

```@example output
collect(Base.pairs(draws[1]))
```

A plain vector carries no chain metadata, so `discard_initial` and `thinning` leave no trace in
the result the way they do in the chain formats. Draws from different chains are separate
vectors.

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
using MCMCChains
chain = AbstractMCMC.from_samples(Chains, reshape(draws, :, 1))
summarystats(chain)
```

```julia
using FlexiChains
chain = AbstractMCMC.from_samples(VNChain, reshape(draws, :, 1))
```

For [ArviZ.jl](https://julia.arviz.org), convert to `Chains` first and pass the result to
`ArviZ.from_mcmcchains`.

## Supporting a new sampler

A sampler works with all three formats once it implements a single method that unpacks its
transitions:

```julia
function JuliaBUGS.transition_params_and_stats(::BUGSModel, ts::Vector{<:MyTransition}, ::MySampler)
    param_samples = [t.params for t in ts]
    stats_names = [:lp]
    stats_values = [[t.lp] for t in ts]
    return param_samples, stats_names, stats_values
end
```

`param_samples[i]` is the flat parameter vector of draw `i`, ordered as
`LogDensityProblems.logdensity` expects it. Statistic values may be arrays; `Chains` flattens
them itself.
