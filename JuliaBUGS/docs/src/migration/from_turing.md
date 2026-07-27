# Coming from Turing.jl

JuliaBUGS lives in the same TuringLang ecosystem as Turing.jl. Sampling goes through the same
AbstractMCMC interface with the same samplers (for example NUTS from AdvancedHMC), gradients are
selected the same way through ADTypes, and results come back as the same chain objects
(FlexiChains or MCMCChains) that work with the plotting and diagnostics tools you already use.

What changes is the modeling paradigm. A Turing model is an imperative Julia program that is run
to produce log densities. A JuliaBUGS model is a *declarative* description of a directed graphical
model: the compiler reads your statements, works out which variable depends on which, and builds
an explicit graph. Statement order does not matter, and loops describe structure rather than
computation.

## The same model, twice

A small hierarchical (random-effects) model of `J` group means. First, roughly how it looks in
Turing.jl — this code is illustrative only; Turing is a separate package and is not used here:

```julia
using Turing  # illustrative — not a JuliaBUGS dependency

@model function schools(y, sigma_y, J)
    mu ~ Normal(0, 100)
    tau ~ truncated(Cauchy(0, 5); lower = 0)
    theta ~ filldist(Normal(mu, tau), J)
    for j in 1:J
        y[j] ~ Normal(theta[j], sigma_y[j])
    end
end

posterior = schools(y_obs, sigma_y, 8)
```

The same model in JuliaBUGS, using classic BUGS distributions (note that `dnorm` takes a mean and
a *precision*, as in WinBUGS and JAGS):

```julia
using JuliaBUGS

eight_schools = @bugs begin
    mu ~ dnorm(0, 1.0E-4)
    tau ~ dgamma(0.001, 0.001)
    for j in 1:J
        theta[j] ~ dnorm(mu, tau)
        y[j] ~ dnorm(theta[j], prec_y[j])
    end
end

model = eight_schools((; y = y_obs, prec_y = 1 ./ sigma_y .^ 2, J = 8))
```

Two differences stand out. Data is not passed as function arguments: the model definition is
compiled against a `NamedTuple` of data, and whichever variables appear in the data are treated
as observed. And because the program is declarative, you could reorder the statements freely —
the graph would be identical.

If you prefer writing models as Julia functions with access to your own functions and imports,
JuliaBUGS also provides its own Julia-native `@model` macro; see
[Defining Models with `@model`](../model_macro.md) and
[Two Macros](../two_macros.md) for how it relates to `@bugs`.

## What the graph buys you

- **An inspectable model.** The compiled model *is* an explicit directed acyclic graph. You can
  query parent–child relationships and [plot the graph](../graph_plotting.md) to check that the
  model you wrote is the model you meant.
- **Conditioning and interventions by name.** Because every variable is a node, you can condition
  on a variable after the fact, or *fix* it to a constant — the graph-surgery equivalent of
  Pearl's do-operator — for what-if and sensitivity analysis. See
  [Fixing Variables](../inference/fixing.md).
- **Block Gibbs sampling.** The graph's conditional-independence structure supports a Gibbs
  sampler in which you assign a different sampler to each block of parameters — for example NUTS
  for the continuous block and Metropolis–Hastings for the rest.
- **Automatic marginalization of discrete variables.** Finite discrete latent variables can be
  summed out exactly and automatically, so models with discrete latents (mixtures, latent classes)
  can still be sampled with gradient-based methods like NUTS. See
  [Auto-Marginalization](../inference/auto_marginalization.md).
- **The classic BUGS corpus.** `@bugs` accepts both Julia-style and original BUGS syntax, so
  decades of published WinBUGS/JAGS models run with little or no translation. The Volume 1
  examples ship with the package; see the [examples](../examples/index.md).

## What you give up

Declarative structure is a real restriction, and it is worth being honest about it:

- **No arbitrary control flow.** Loops and `if` statements are structural: they must be resolvable
  from the data when the model is compiled. You cannot write a `while` loop, recursion, or code
  whose shape depends on sampled values.
- **No stochastic branching.** A model cannot take one branch or another depending on the value of
  a latent variable; every model instance is one fixed graph.
- **A restricted function set inside `@bugs`.** Only the BUGS primitives (`dnorm`, `dgamma`,
  `exp`, `log`, ...) are available by default. Your own functions must be registered with
  `@bugs_primitive` first — or use the Julia-native [`@model` macro](../model_macro.md), which has
  full access to functions in your module.

If your model genuinely needs simulation-like code inside the model body, Turing.jl remains the
better fit.

## Practical notes

Once the model is built, inference looks almost exactly like Turing's AbstractMCMC usage:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains

# adtype enables gradient computation, needed by NUTS/HMC
model = eight_schools((; y = y_obs, prec_y = 1 ./ sigma_y .^ 2, J = 8);
                  adtype = AutoMooncake(; config = nothing))

chain = AbstractMCMC.sample(
    model, NUTS(0.8), 2000;
    chain_type = VNChain, n_adapts = 1000, discard_initial = 1000,
)
summarystats(chain)
```

The resulting chain is a standard FlexiChains object (pass `chain_type = MCMCChains.Chains` if you
prefer MCMCChains), so your existing diagnostics, plotting, and post-processing code carries over
unchanged. Initial values can be supplied with `initialize!(model, inits)` or via `init_params`.

For a full walkthrough from installation to results, start with
[Getting Started](../getting_started.md).
