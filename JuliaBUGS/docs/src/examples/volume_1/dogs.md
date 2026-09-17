# Dogs: Loglinear Model for Binary Data

This example comes from the Solomon-Wynne avoidance-learning experiment, in which 30 dogs were each put through 25 identical trials. On every trial a barrier was raised and, ten seconds later, an electric shock was delivered unless the dog jumped the barrier first. The outcome recorded for each dog on each trial is binary: the dog either avoided the shock (a success) or was shocked (a failure). Over repeated trials the dogs learn, so the chance of being shocked falls as a dog accumulates experience.

The model answers the question of *how* that learning accumulates: it lets each previous avoidance and each previous shock multiply the probability of being shocked on the current trial by its own constant factor. This is a loglinear model for binary data — the log of the shock probability is a linear function of how many shocks the dog has so far avoided and how many it has received. It is one of the examples in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Dogs.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.dogs`, which ships with the package.

## Model

Let $x^{a}_{ij}$ be the number of shocks dog $i$ has *avoided* before trial $j$ and $x^{s}_{ij} = (j-1) - x^{a}_{ij}$ the number of shocks it has *received*. Writing $p_{ij}$ for the probability that dog $i$ is shocked on trial $j$, the model is

```math
\begin{aligned}
\log p_{ij} &= \alpha\, x^{a}_{ij} + \beta\, x^{s}_{ij}, \\
y_{ij} &\sim \text{Bernoulli}(p_{ij}),
\end{aligned}
```

where $y_{ij} = 1 - Y_{ij}$ is the indicator that a shock occurred on trial $j$. Both learning coefficients are constrained to be negative through uniform priors, $\alpha, \beta \sim \text{Uniform}(-10, -0.00001)$, so that each additional past avoidance or shock can only reduce the probability of a further shock. Equivalently, $p_{ij} = A^{x^{a}_{ij}} B^{x^{s}_{ij}}$ with the per-event multipliers $A = \exp(\alpha)$ and $B = \exp(\beta)$. The first trial carries no prior history, so the likelihood runs from the second trial onward.

```@example dogs
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.dogs
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example dogs
print(example.original_syntax_program)
```

## Data

The data are supplied as a `NamedTuple`: the number of dogs `Dogs`, the number of trials per dog `Trials`, and the 30-by-25 matrix `Y`, whose entry `Y[i, j]` is 1 if dog `i` avoided the shock on trial `j` and 0 if it was shocked.

```@example dogs
data = example.data
```

```@example dogs
model = compile(example.model_def, data)
```

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.dogs.inits` and can be applied with `initialize!(model, inits)`.

## Results

This example does not ship packaged reference posterior summaries — its `reference_results` field is `nothing` — so there is no built-in table to reproduce here. Published posterior summaries for the two learning coefficients $\alpha$ and $\beta$ (and the derived per-event multipliers $A$ and $B$) are given on the [MultiBUGS](https://www.multibugs.org/examples/latest/VolumeI.html) and [OpenBUGS](https://chjackson.github.io/openbugsdoc/Examples/Dogs.html) Dogs pages. A correctly converged chain's `summarystats` should reproduce those published values up to Monte Carlo error.

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
