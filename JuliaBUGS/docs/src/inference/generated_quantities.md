# Generated Quantities

A **generated quantity** is an unobserved node — stochastic or deterministic — that is
outside the log-density target dependency closure. In a model with observations, this usually
means the node has **no observed descendants**: no directed path leads from it to any
observation. Because it cannot influence the target density over the model parameters,
JuliaBUGS keeps generated quantities *out of the inference target* and recovers them
afterwards by forward sampling.

Typical generated quantities are posterior-predictive draws, derived summaries, or latent
states you want to report but not sample directly:

```julia
predictive_model = @bugs begin
    mu ~ Normal(0, 1)
    y ~ Normal(mu, 1)        # observed
    y_pred ~ Normal(mu, 1)   # generated quantity (no observed descendant)
    excess = y_pred - mu     # deterministic generated quantity
end
model = predictive_model((; y = 0.5))
```

Here `mu` is a model parameter, `y` is an observation, and `y_pred` and `excess` are
generated quantities.

## Classification

Every node is assigned a [`VariableType`](@ref JuliaBUGS.VariableType): `Observation`, `ModelParameter`,
`TransformedParameter`, or `GeneratedQuantity`. The partition that matters for inference is:

- **Model parameters** — unobserved stochastic nodes in the target. These are what MCMC
  samples; they make up the parameter vector and the dimension.
- **Transformed parameters** — deterministic nodes needed to evaluate the target density.
- **Generated quantities** — unobserved nodes outside the target dependency closure.

The two sets are disjoint, and no model parameter or observation ever has a generated
quantity as an ancestor.

```julia
JuliaBUGS.model_parameters(model)      # [mu]
JuliaBUGS.generated_quantities(model)  # [y_pred, excess]
JuliaBUGS.variable_type(model, @varname(y_pred))  # GeneratedQuantity
```

`parameters(model)` returns all unobserved stochastic nodes (model parameters together with
the stochastic generated quantities); `model_parameters(model)` returns only the nodes that
are actually sampled and counted in `LogDensityProblems.dimension`.

## Log density

Generated quantities are excluded from the log density in **every** [evaluation
mode](evaluation_modes.md):

```julia
using LogDensityProblems
LogDensityProblems.dimension(model)                  # 1 (mu only; y_pred/excess excluded)
LogDensityProblems.logdensity(model, getparams(model))  # depends only on mu
```

This holds for `UseGraph`, `UseGeneratedLogDensityFunction` (the generated function drops the
generated-quantity statements), and `UseAutoMarginalization` (the marginalization skips
them). The log density is therefore identical across modes for the same parameter values.

## Forward sampling

After obtaining posterior draws of the model parameters, recover the generated quantities for
each draw with [`forward_sample_generated_quantities!!`](@ref JuliaBUGS.Model.forward_sample_generated_quantities!!). It visits the generated
quantities in topological order, drawing stochastic ones from their conditional distribution
and recomputing deterministic ones, leaving model parameters and observations untouched:

```julia
using Random
env, _ = AbstractPPL.evaluate!!(model, getparams(model))  # set parameters
env = JuliaBUGS.Model.forward_sample_generated_quantities!!(Random.default_rng(), model, env)
AbstractPPL.getvalue(env, @varname(y_pred))   # a posterior-predictive draw
```

When you build a chain with `JuliaBUGS.gen_chains`, this step is applied automatically, so the
reported generated quantities are genuine posterior(-predictive) draws.

### Under auto-marginalization

If the model is in `UseAutoMarginalization` mode, its discrete latents were summed out of the
log density and carry no value. A generated quantity may nonetheless depend on such a latent
``z``. Before forward sampling, `forward_sample_generated_quantities!!` first recovers the
latents from their conditional posterior ``p(z \mid \theta, y)``: each latent is drawn in
topological order from the weights ``p(z_i = v \mid \mathrm{pa}) \cdot p(y, z_{>i} \mid z_i =
v, \dots)``, where the second factor is the marginalized joint of everything downstream.
Normalizing over ``v`` gives exactly ``p(z_i = v \mid z_{<i}, \theta, y)``, so the latents are
drawn jointly from ``p(z \mid \theta, y)`` and the dependent generated quantity is then
sampled from the recovered ``z``. Generated quantities with no marginalized-discrete ancestor
are unaffected.

## Models with no observations

If a model has **no** observations at all, JuliaBUGS does *not* treat every node as a
generated quantity (which would leave nothing to sample). Instead all unobserved stochastic
nodes are kept as model parameters, so the model is sampled as the full prior. Deterministic
ancestors of those stochastic parameters are transformed parameters and are recomputed during
log-density evaluation. Terminal deterministic nodes that do not feed any stochastic factor
can still be generated quantities.

For example, in this prior-only model `h` is **not** a generated quantity because the prior
factor for `y` depends on it:

```julia
prior_model = @bugs begin
    x ~ Normal(0, 1)
    h = x + 1
    y ~ Normal(h, 1)
end
model = prior_model((;))
JuliaBUGS.variable_type(model, @varname(h))  # TransformedParameter
```

Add data (or `condition` on some variables) to obtain the usual observed-data
generated-quantity partition.

## API

```@docs
JuliaBUGS.generated_quantities
JuliaBUGS.model_parameters
JuliaBUGS.variable_type
JuliaBUGS.VariableType
JuliaBUGS.Model.forward_sample_generated_quantities!!
```
