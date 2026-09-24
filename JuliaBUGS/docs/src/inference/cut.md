# Cut Inference (`cut` / `NestedCut`)

Sometimes downstream data should not feed back into the upstream parameters: feedback
from a poorly specified downstream module can contaminate estimates of the parameters of
interest. The **cut distribution** (Plummer 2015) prevents this. If the model splits into
an upstream module ``\{\varphi, Z\}`` and a downstream module ``\{\theta, Y\}`` separated
by a cut, the cut distribution is

```math
p_{\mathrm{cut}}(\varphi, \theta) = p(\varphi \mid Z)\, p(\theta \mid \varphi, Y),
```

where ``p(\varphi \mid Z)`` is the posterior of the upstream parameters using only the
upstream data ``Z`` — it ignores ``Y`` entirely. Compared to the full posterior
``p(\varphi \mid Z, Y)``, the upstream factor is missing the likelihood ``p(Y \mid \varphi)``
through the downstream module: information flows "down" to ``\theta`` but never back "up"
to ``\varphi``.

## Marking the boundary with `cut`

Wrap the upstream variable that feeds the downstream module in `cut` and assign it to a
new name; downstream nodes must use the cut name:

```julia
using JuliaBUGS

model_def = @bugs begin
    phi ~ dnorm(0, 1)
    Z ~ dnorm(phi, 1)          # upstream data
    phi_cut = cut(phi)         # the cut: everything downstream sees phi_cut
    theta ~ dnorm(0, 1)
    Y ~ dnorm(phi_cut + theta, 1)  # downstream data
end
model = compile(model_def, (; Z=1.0, Y=3.0))
```

`cut(x)` is just the identity function — the model's joint density is unchanged. It only
marks where the graph is severed for inference.

With `@model`, bring `cut` into scope with `using JuliaBUGS.BUGSPrimitives: cut`:

```julia
using JuliaBUGS.BUGSPrimitives: cut

@model function cut_model((; Z, Y))
    phi ~ Normal(0, 1)
    Z ~ Normal(phi, 1)
    phi_cut = cut(phi)
    theta ~ Normal(0, 1)
    Y ~ Normal(phi_cut + theta, 1)
end
model = cut_model((; Z=1.0, Y=3.0))
```

## The module partition

`JuliaBUGS` partitions the graph at the cut nodes:

- **Module 2 (downstream)** is the union of the weakly connected components that contain
  a descendant of a cut node, in the graph with the cut nodes removed.
- **Module 1 (upstream)** is everything else, including the cut nodes themselves.

An `ArgumentError` is raised when the cut does not separate the model — i.e. when an
ancestor of a cut node ends up in module 2 (for example, a variable shared by both
modules without passing through the cut).

Two derived models expose the partition:

- `cut_upstream_model(model)` targets ``p(\varphi \mid Z)``: module-2 stochastic nodes are
  dropped from the target and classified as generated quantities.
- `cut_downstream_model(model)` targets ``p(\theta \mid \varphi, Y)``: the module-1
  parameters are `fix`ed at their values in `model.evaluation_env`.

```julia
using JuliaBUGS.Model: cut_upstream_model, cut_downstream_model, model_parameters

upstream = cut_upstream_model(model)      # model_parameters(upstream) == [phi]
downstream = cut_downstream_model(model)  # model_parameters(downstream) == [theta]; phi is FixedParameter
```

## `NestedCut`

`NestedCut(upstream_sampler, downstream_sampler)` runs nested MCMC for the cut
distribution. Each outer step draws ``\varphi`` from the upstream model (one transition of
`upstream_sampler`), then runs `inner_steps` transitions of `downstream_sampler` on the
downstream model with ``\varphi`` fixed at the new draw:

```julia
using AdvancedMH: RWMH
using Distributions: Normal

sampler = NestedCut(
    RWMH([Normal(0, 0.7)]),   # kernel for phi
    RWMH([Normal(0, 0.7)]);   # kernel for theta
    inner_steps=5,
)
chain = sample(rng, model, sampler, 10_000; progress=false)
```

Stage samplers accept the same kinds as [`Gibbs`](@ref) blocks: an AdvancedMH/AdvancedHMC/
SliceSampling sampler, a `(sampler, adtype)` tuple such as
`(NUTS(0.65), AutoForwardDiff())`, `EnumeratedSampler()`, or a `Gibbs` built on the
corresponding derived model, e.g. `Gibbs(cut_upstream_model(model), RWMH(1))`.

Two keyword arguments control the inner chain:

- `inner_steps` (default `10`): how many downstream transitions run per outer draw. The
  exact cut distribution requires the inner chain to converge at each ``\varphi``, so a
  finite `inner_steps` is an approximation whose bias shrinks as `inner_steps` grows; a
  single inner step is exact only when the downstream kernel is itself an exact draw
  (e.g. `EnumeratedSampler`).
- `warm_start` (default `true`): the inner chain continues from the previous ``\theta``
  each outer step, so ``\theta`` follows a Markov chain across the whole run. With
  `warm_start=false`, ``\theta`` is redrawn from its (conditional) prior before each inner
  run.

Chain output goes through the usual `bundle_transitions`/`gen_chains` path on the
*original* model, so `MCMCChains.Chains` and `FlexiChains` chain types work unchanged and
each draw contains both ``\varphi`` and ``\theta``. The reported `lp` is the full-model
joint log density at the draw, not the cut density.

## Reference

Plummer, M. (2015). "Cuts in Bayesian graphical models". *Statistics and Computing*,
25(1), 37–43.

## API

```@docs
JuliaBUGS.BUGSPrimitives.cut
JuliaBUGS.NestedCut
JuliaBUGS.Model.cut_upstream_model
JuliaBUGS.Model.cut_downstream_model
```
