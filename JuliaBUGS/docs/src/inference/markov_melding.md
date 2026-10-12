# Markov Melding (`meld`)

```@meta
CurrentModule = JuliaBUGS.Melding
```

**Markov melding** joins several Bayesian submodels that share a quantity into one joint
model, and lets you fit the joint model from the submodels without rewriting them. It was
introduced by Goudie, Presanis, Lunn, De Angelis and Wernisch,
[*Joining and Splitting Models with Markov Melding*](https://doi.org/10.1214/18-BA1104),
Bayesian Analysis 14(1), 2019, who developed it for evidence synthesis in BUGS, where an
analysis is often built from separately specified components that each inform a common
parameter.

[`meld`](@ref) takes a vector of compiled `BUGSModel`s and the name of the shared quantity in
each, and returns a [`MeldedModel`](@ref): a `LogDensityProblems` target whose density is the
Markov melded posterior. It can be sampled with any sampler that accepts a log density, such
as NUTS from AdvancedHMC.

```@example melding
using JuliaBUGS
using JuliaBUGS.Melding
using AbstractMCMC, AdvancedHMC, ADTypes, DifferentiationInterface, ForwardDiff
using Distributions, LogDensityProblems, Random, Statistics

JuliaBUGS.@bugs_primitive Normal Gamma LogNormal exp sqrt
nothing # hide
```

## The melded posterior

Suppose there are ``M`` submodels. Submodel ``m`` has parameters ``(\phi, \psi_m)``,
where ``\phi`` is the **link**, the quantity common to all submodels, and ``\psi_m`` are the
parameters private to submodel ``m``. With prior ``p_m(\phi, \psi_m)`` and data ``y_m`` the
submodel has joint density ``p_m(\phi, \psi_m, y_m) = p_m(\phi, \psi_m)\, p_m(y_m \mid \phi, \psi_m)``
and **prior marginal** of the link

```math
p_m(\phi) = \int p_m(\phi, \psi_m)\, d\psi_m .
```

The submodels generally disagree about the prior of ``\phi``, so they cannot simply be
multiplied. Markov melding replaces each submodel's marginal for ``\phi`` by a common
**pooled** marginal ``p_{\text{pool}}(\phi) = g\big(p_1(\phi), \ldots, p_M(\phi)\big)`` and then
combines the submodels as a *Markov combination*: the common prior times the submodel
conditionals ``p_m(\psi_m, y_m \mid \phi)``, which is the joint model one would write by hand
when the submodels are conditionally independent given ``\phi``. That conditional
independence, ``(\psi_m, y_m) \perp (\psi_\ell, y_\ell) \mid \phi`` for ``m \neq \ell``, is the
modelling assumption behind melding. The melded model is

```math
p_{\text{meld}}(\phi, \psi_1, \ldots, \psi_M, y_1, \ldots, y_M)
  = p_{\text{pool}}(\phi) \prod_{m=1}^{M} \frac{p_m(\phi, \psi_m, y_m)}{p_m(\phi)}
  = p_{\text{pool}}(\phi) \prod_{m=1}^{M} p_m(\psi_m, y_m \mid \phi),
```

and conditioning on the data gives the melded posterior, equation 6 of the paper,

```math
p_{\text{meld}}(\phi, \psi_1, \ldots, \psi_M \mid y_1, \ldots, y_M)
  \;\propto\; p_{\text{pool}}(\phi) \prod_{m=1}^{M} \frac{p_m(\phi, \psi_m, y_m)}{p_m(\phi)} .
```

Each factor in the product is "submodel ``m`` with its own opinion about ``\phi`` divided out";
the pooled prior then puts a single opinion back in. Goudie et al. show that replacing a
submodel's marginal in this way is the modification that stays closest to the submodel: it
minimises the Kullback–Leibler divergence ``D_{KL}(q \,\|\, p_m)`` among all densities ``q``
with ``q(\phi) = p_{\text{pool}}(\phi)`` (Supplementary Material A of the paper).

When the link is a deterministic function ``\phi = h(\theta_m)`` of some of a submodel's
parameters ``\theta_m``, as when a submodel's parameters determine a prevalence that another
submodel treats as a parameter, the same formula applies with the submodel's joint density
over ``\theta_m`` in the numerator and the implied prior marginal ``p_m(h(\theta_m))`` in the
denominator (equation 4 of the paper).

### Pooling rules

The choice of ``g`` is up to the analyst. `meld` provides four rules. Writing the melded log
density as

```math
\sum_m \log p_m(\phi, \psi_m, y_m) \;+\; \sum_m a_m \log p_m(\phi) \;+\; e(\phi),
```

up to an additive constant that does not depend on ``\phi``, each rule is characterised by
the exponents ``a_m`` it puts on the submodel marginals and an extra term ``e``, which
determine which marginals enter the density at all:

| Pooling | ``p_{\text{pool}}(\phi)`` | ``a_m`` | ``e(\phi)`` | ``p_m(\phi)`` enters for |
|:--|:--|:--|:--|:--|
| [`ProductOfExperts`](@ref) | ``\propto \prod_m p_m(\phi)`` | ``0`` | ``0`` | no submodel |
| [`Dictatorial`](@ref)`(k)` | ``p_k(\phi)`` | ``-1`` for ``m \ne k``, ``0`` for ``k`` | ``0`` | all but ``k`` |
| [`LogarithmicPooling`](@ref)`(λ)` | ``\propto \prod_m p_m(\phi)^{\lambda_m}`` | ``\lambda_m - 1`` | ``0`` | those with ``\lambda_m \ne 1`` |
| [`LinearPooling`](@ref)`(λ)` | ``\sum_m \lambda_m p_m(\phi)`` | ``-1`` | ``\log \sum_m \lambda_m p_m(\phi)`` | all, normalised |

Product of experts is free of marginals because every ``p_m(\phi)`` cancels, but the pooled
prior is typically more concentrated than the individual priors, and more so with every
submodel added. Dictatorial pooling keeps one submodel's prior unchanged. Logarithmic
pooling with equal weights ``1/M`` is the geometric mean and does not concentrate as ``M``
grows. Linear pooling is a mixture and needs every marginal as a properly normalised density.

Whether a marginal enters the formula is not the same as whether you have to supply one.
As the next section explains, a term ``p_m(\phi)^{-1}`` for a *closed* link is removed exactly
from the graph and needs no marginal object, and other closed links get an exact marginal
automatically. You only supply a marginal for a link that is a logical node or has
stochastic ancestors outside the link.

## How JuliaBUGS evaluates it

A BUGS model is a directed acyclic graph, and its log density is a sum of one term per
stochastic node, ``\log p(v \mid \mathrm{pa}(v))``. This makes the melded density a graph
operation rather than a numerical one:

- **Closed links.** A link is *closed* in a submodel when every link node is an unobserved
  stochastic node and every stochastic ancestor of a link node is itself a link node. The
  usual case is ``\phi`` being a root node with its own prior. The link's own factor then *is*
  ``p_m(\phi)``, and dividing by ``p_m(\phi)`` means leaving that one node out of the sum. That
  is exactly what [`fix`](fixing.md) does: it holds the node at a value, lets its descendants
  read the value, and does not score it. No integral, no estimate, no second copy of the
  prior that could go stale. `meld` uses `fix` when the pooling divides ``p_m(\phi)`` out
  exactly once (``a_m = -1``), the link is closed, and you have not supplied a marginal for
  that submodel.
- **Keeping a factor.** In every other case, a kept factor (``a_m = 0``), a fractional power
  under logarithmic pooling, or a link with stochastic ancestors outside the link, `meld`
  uses `condition`, which holds the value *and* scores the node, and adds the remaining
  power of ``p_m(\phi)`` from a marginal.
- **The carrier.** One submodel keeps the link in its parameter vector and is evaluated
  whole, so the link's own transform and Jacobian are counted exactly once. It is the
  submodel in which the link is a logical node if there is one; otherwise the dictator,
  provided it samples the link as a model parameter; otherwise the first submodel that does.
  Every other submodel is evaluated at the carrier's link value, with the link fixed or
  conditioned. The values live in each submodel's *evaluation environment*, the named tuple
  of all variable values that JuliaBUGS evaluates a model against.
- **Marginals.** Whatever power of ``p_m(\phi)`` the pooling still requires is added from an
  [`AbstractMarginal`](@ref): an [`ExactMarginal`](@ref), read off the graph for a closed
  link, or a [`SimulatedMarginal`](@ref) or [`FunctionMarginal`](@ref) that you supply when
  the link is a logical node or has stochastic ancestors outside the link.

The melded parameter vector is the concatenation of the prepared submodels' parameter
vectors, each in that submodel's own (transformed) space. The link appears once, in the
carrier's block.

## Example: joining two submodels on a shared parameter

Two studies measure the same quantity `phi`. The first has an unknown precision, the second
measures `phi` through a product with a nuisance parameter. Each is a complete model on its
own:

```@example melding
study1_def = @bugs begin
    phi ~ Normal(0, 1)
    tau ~ Gamma(2, 1)
    for i in 1:3
        y[i] ~ Normal(phi, 1 / sqrt(tau))
    end
end
study2_def = @bugs begin
    phi ~ Normal(0, 1)
    gam ~ Normal(0, 1)
    for j in 1:2
        x[j] ~ Normal(phi * gam, 1)
    end
end
study1 = study1_def((; y = [0.3, -0.2, 1.1]))
study2 = study2_def((; x = [0.5, 0.7]))
nothing # hide
```

Melding them is one call. The second argument names the link in each submodel; the names
may differ between submodels as long as they denote the same quantity on the same scale.

```@example melding
melded = meld([study1, study2], [:phi, :phi]; pooling = Dictatorial(1))
```

Submodel 1 is the carrier and keeps its prior on `phi`; in submodel 2 the link is a closed
root node and dictatorial pooling divides its prior out, so `meld` fixed it, which needs no
marginal. The parameter vector has three entries:

```@example melding
parameter_names(melded)
```

Dictatorial pooling towards submodel 1 reproduces the joint model one would have written
by hand, whatever prior submodel 2 had put on `phi`, because that prior is divided out. We
can check this pointwise, which is a much stronger test than comparing posterior summaries:

```@example melding
joint_def = @bugs begin
    phi ~ Normal(0, 1)
    tau ~ Gamma(2, 1)
    for i in 1:3
        y[i] ~ Normal(phi, 1 / sqrt(tau))
    end
    gam ~ Normal(0, 1)
    for j in 1:2
        x[j] ~ Normal(phi * gam, 1)
    end
end
joint = joint_def((; y = [0.3, -0.2, 1.1], x = [0.5, 0.7]))

# Parameter vectors at the same constrained values, in each model's own layout.
using JuliaBUGS.Model: getparams, initialize!
vals = (; phi = 0.4, tau = 1.7, gam = -0.3)
x_joint = getparams(initialize!(joint, vals))
x_meld = vcat(getparams(initialize!(melded.prepared[1], vals)),
              getparams(initialize!(melded.prepared[2], vals)))

LogDensityProblems.logdensity(melded, x_meld) ≈ LogDensityProblems.logdensity(joint, x_joint)
```

Product of experts multiplies both priors in, so it differs from the joint by exactly one
extra copy of the `Normal(0, 1)` log density of `phi`:

```@example melding
poe = meld([study1, study2], [:phi, :phi]; pooling = ProductOfExperts())
LogDensityProblems.logdensity(poe, x_meld) - LogDensityProblems.logdensity(joint, x_joint) ≈
    logpdf(Normal(0, 1), 0.4)
```

### Sampling

A `MeldedModel` is sampled like any log density. For gradient-based samplers pass an AD
backend, which wraps the model in a [`MeldedModelWithGradient`](@ref):

```@example melding
chain = AbstractMCMC.sample(
    Random.Xoshiro(1), melded, NUTS(0.8), 1_500;
    adtype = AutoForwardDiff(), n_adapts = 500, discard_initial = 500, progress = false,
)
draws = reduce(hcat, t.z.θ for t in chain)   # 3 × 1000, rows follow parameter_names(melded)
mean(draws; dims = 2)
```

[`evaluation_envs`](@ref) maps a point of the melded parameter vector back to named values,
one evaluation environment per submodel, with the link written into all of them:

```@example melding
envs = evaluation_envs(melded, chain[end].z.θ)
(envs[1].phi, envs[2].phi, envs[1].tau, envs[2].gam)
```

## Example: a link that is a deterministic function of one submodel's parameters

In evidence synthesis the link is often a *derived* quantity in one submodel. Here the
first submodel has a parameter `theta` on the log scale and defines `phi = exp(theta)`,
while the second treats `phi` directly as a parameter with a `LogNormal(0, 1)` prior.

```@example melding
owner_def = @bugs begin
    theta ~ Normal(0, 1)
    phi = exp(theta)
    y ~ Normal(theta, 1)
end
other_def = @bugs begin
    phi ~ LogNormal(0, 1)
    x ~ Normal(phi, 1)
end
owner = owner_def((; y = 0.4))
other = other_def((; x = 1.2))

melded_logical = meld([owner, other], [:phi, :phi]; pooling = Dictatorial(1))
```

The submodel that defines the link deterministically is always the carrier, since the link
is a function of its parameters. Nothing observed in `owner` depends on `phi`, so JuliaBUGS
classifies it as a [generated quantity](generated_quantities.md) there; `meld` recomputes it
after each evaluation of the carrier so the other submodels see the current value.

Pooling towards the *other* submodel needs the prior marginal of `phi` implied by `owner`,
``p_1(\phi)``, which here we know analytically: `exp` of a standard normal is `LogNormal(0, 1)`.
When it is not known, estimate it by prior simulation. [`SimulatedMarginal`](@ref) draws from
the submodel's prior, maps the link through a transform to an unconstrained scale, and fits a
density there; `transform = log` is the right choice for a positive link:

```@example melding
estimated = SimulatedMarginal(owner, :phi; n = 20_000, rng = Random.Xoshiro(2), transform = log)
grid = exp.(range(-1.5, 1.5; length = 5))
[logmarginal(estimated, [g]) - logpdf(LogNormal(0, 1), g) for g in grid]
```

The estimate is within a few hundredths of the exact log density over the central range.
Either can be passed to `meld`, keyed by the index of the submodel it belongs to:

```@example melding
with_exact = meld([owner, other], [:phi, :phi];
                  pooling = Dictatorial(2), marginals = Dict(1 => LogNormal(0, 1)))
with_estimate = meld([owner, other], [:phi, :phi];
                     pooling = Dictatorial(2), marginals = Dict(1 => estimated))
(LogDensityProblems.logdensity(with_exact, [0.2]), LogDensityProblems.logdensity(with_estimate, [0.2]))
```

!!! warning "Estimated marginals sit in a denominator"
    ``p_m(\phi)`` divides the melded density, so errors in the tails of an estimate are
    amplified exactly where the sampler explores least. Fit on an unconstrained scale, check
    the estimate against an exact marginal whenever one is available, prefer
    `estimator = :normal` when the transformed draws look Gaussian, and increase `n` when they
    do not. Manderson and Goudie, *A numerically stable algorithm for integrating Bayesian
    models using Markov melding* (Statistics and Computing, 2022), discuss the failure modes.

## Example: a link with a hierarchical prior

The case BUGS users meet most often is a link whose prior has its own parameters, such as
`phi ~ Normal(mu, 1)` with `mu` unknown. The link is then *open* in that submodel: it has a
stochastic ancestor, `mu`, outside the link, so its factor in the graph is the conditional
``p(\phi \mid \mu)`` rather than the marginal ``p_m(\phi)``, and `fix` would remove the wrong
thing.

```@example melding
hier_def = @bugs begin
    mu ~ Normal(0, 1)
    phi ~ Normal(mu, 1)
    y ~ Normal(phi, 1)
end
flat_def = @bugs begin
    phi ~ Normal(0, sqrt(2))
    x ~ Normal(phi, 1)
end
hier = hier_def((; y = 0.5))
flat = flat_def((; x = -0.5))

meld([hier, flat], [:phi, :phi]; pooling = Dictatorial(1))
```

Pooling towards `hier` is still exact: `hier` is the carrier, evaluated whole, and `flat`
has a closed link that is fixed. Pooling towards `flat` needs the marginal of `phi` under
`hier`, and `meld` says so:

```@example melding
try
    meld([hier, flat], [:phi, :phi]; pooling = Dictatorial(2))
catch err
    println(err.msg)
end
```

Here the marginal is known, ``\phi \sim \mathrm{Normal}(0, \sqrt{2})``, and could be passed as a
`Distribution`. In general it is estimated by prior simulation; the link is real-valued, so
no transform is needed and a Gaussian fit is appropriate:

```@example melding
hier_marginal = SimulatedMarginal(hier, :phi; n = 20_000, rng = Random.Xoshiro(3), estimator = :normal)
hier_marginal.density
```

```@example melding
towards_flat = meld([hier, flat], [:phi, :phi];
                    pooling = Dictatorial(2), marginals = Dict(1 => hier_marginal))
```

`hier` is conditioned on the link rather than fixed, so `mu` stays in the target with its
factor ``p(\phi \mid \mu)``, and the estimated ``p_1(\phi)`` is divided out.

## Example: splitting a model and melding it back

The paper's second use of melding is in the other direction: a large joint model is split
into pieces that can be fitted separately, then melded to recover inference under the joint
model. `meld` supports this directly, and it is the natural correctness test for any melding
set-up. Take the joint model above, split it at `phi` into `study1` and `study2`, and meld
with dictatorial pooling towards the side that kept the original prior on `phi`. The melded
log density equals the joint log density at every point, as the check in the first example
showed, whatever prior the other side was given. If both sides carry the original prior,
the same holds for any pooling whose rule maps identical marginals to themselves, such as
logarithmic pooling with weights summing to one:

```@example melding
geo = meld([study1, study2], [:phi, :phi]; pooling = LogarithmicPooling([0.5, 0.5]))
LogDensityProblems.logdensity(geo, x_meld) ≈ LogDensityProblems.logdensity(joint, x_joint)
```

## Choosing a pooling rule and supplying marginals

- Start with [`Dictatorial`](@ref) pooling towards the submodel whose prior on the link you
  trust, or [`ProductOfExperts`](@ref) when every submodel's prior is vague and you accept
  the concentration. Neither needs an estimated marginal when the links are closed.
- Use [`LogarithmicPooling`](@ref) with equal weights to average the submodels' priors
  without concentrating. Use [`LinearPooling`](@ref) when the priors genuinely represent
  alternative hypotheses and a mixture is wanted; expect a possibly multimodal pooled prior.
- `meld` throws an informative `ArgumentError` naming the submodel when a marginal is needed
  and the link is not closed. Supply it through `marginals = Dict(m => ...)`, as an
  [`AbstractMarginal`](@ref), a `Distribution`, or a function of the link value returning the
  log density.
- A supplied marginal is always used, even for a closed link where `meld` could have divided
  the prior out exactly with `fix`; that submodel is then conditioned instead.
- A multivariate link is given as a vector of `VarName`s, or as the array name, which expands
  to its element nodes in column-major index order, the order of `vec`. The order must be
  the same in every submodel.

## Limitations

- At most one submodel may define the link as a logical node. If two submodels define
  ``\phi`` deterministically there is nothing to force the definitions to agree.
- A logical link must be a function of its submodel's model parameters. If it also depends
  on an unobserved stochastic node that nothing observed depends on, `meld` raises an error
  rather than silently dropping that node.
- Melding assumes the submodels are conditionally independent given the link, and Goudie
  et al. do not recommend it when the submodels' priors on the link are in substantial
  conflict; inspect the marginals before pooling them.
- All submodels must agree on whether their parameters are in transformed space; use
  `settrans` to align them.
- The melded model is sampled jointly. The multi-stage sampler of Section 4.1 of the paper,
  which reuses posterior draws of one submodel as proposals for the next, is not provided;
  the target it samples is exactly the density `meld` builds.
- Building a `MeldedModel` performs model surgery (`fix` or `condition`) once per
  non-carrier submodel, which is comparatively expensive; evaluating it afterwards only
  swaps the link value into each submodel's evaluation environment. Build once, evaluate
  many times. Held submodels are evaluated by graph evaluation.

## API

```@docs
Melding
meld
MeldedModel
MeldedModelWithGradient
nsubmodels
evaluation_envs
link_value
parameter_names
AbstractPooling
ProductOfExperts
Dictatorial
LogarithmicPooling
LinearPooling
marginal_exponents
needs_all_marginals
logpool_extra
AbstractMarginal
logmarginal
ExactMarginal
SimulatedMarginal
FunctionMarginal
GaussianKDE
LinkInfo
```
