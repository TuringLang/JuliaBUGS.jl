# Fixing Variables (`fix` / `unfix`)

[`fix`](@ref AbstractPPL.fix) sets a stochastic variable to a **known constant**: its value is
used by descendants, but its incoming factor is removed from the target density and the variable
is taken out of the parameter vector. [`unfix`](@ref AbstractPPL.unfix) reverses this.

This contrasts with **conditioning** (`condition`), which treats the value as an *observation*:
the variable's incoming factor is **kept** in the target, so the value still informs its
parents. Fixing instead drops that factor entirely, so the variable's parents no longer explain
it.

Fixing is useful wherever you want to set a variable rather than observe it: "what-if" and
sensitivity analysis, ablations, holding a nuisance parameter constant, and — its canonical
illustration — **causal interventions**, where `fix` is exactly Pearl's *do*-operator
``p(\cdot \mid \mathrm{do}(X = x))`` versus conditioning's ``p(\cdot \mid X = x)``.

The examples below use `Normal` (from Distributions) inside `@bugs` rather than BUGS's built-in
`dnorm`, so we register it as a model primitive first:

```@example fixing
using JuliaBUGS
using AbstractPPL: fix, unfix, condition
using Distributions: Normal, logpdf
using LogDensityProblems

JuliaBUGS.@bugs_primitive Normal
```

Consider a three-node chain with `y` observed:

```@example fixing
chain_def = @bugs begin
    theta ~ Normal(0, 1)
    x ~ Normal(theta, 1)
    y ~ Normal(x, 1)
end
chain = chain_def((; y = 2.0))
```

## Why `fix` differs from `condition`

The two operations give genuinely different distributions whenever the fixed variable has
parents. Fixing `x` cuts the `theta -> x` edge and drops `x`'s own factor, while conditioning on
`x` keeps both. Evaluating the log density of each makes the difference concrete:

```@example fixing
chain_fixed = fix(chain; x = 1.0)        # set x to the constant 1.0
chain_cond  = condition(chain; x = 1.0)  # observe x = 1.0

(fixed_dim        = LogDensityProblems.dimension(chain_fixed),
 fixed_logp       = LogDensityProblems.logdensity(chain_fixed, Float64[]),
 conditioned_dim  = LogDensityProblems.dimension(chain_cond),
 conditioned_logp = LogDensityProblems.logdensity(chain_cond, [0.0]))  # at theta = 0
```

The fixed model scores only `y`'s factor at the set value — `logpdf(Normal(1, 1), 2.0)`. The
conditioned model additionally keeps `theta`'s prior and the `x | theta` factor — at `theta = 0`
that is `logpdf(Normal(0, 1), 0.0) + logpdf(Normal(0, 1), 1.0) + logpdf(Normal(1, 1), 2.0)` — so
observing `x = 1` still updates beliefs about `theta`, and `theta` stays a sampled parameter.
Under `fix`, cutting the edge into `x` leaves `theta` with no observed descendant, so it becomes
a [generated quantity](generated_quantities.md) (recovered by forward sampling, not sampled by
MCMC) and the dimension drops to zero.

## Use case: causal interventions

In causal modeling, `fix` is the *do*-operator, and it earns its keep when there is
**confounding**. Consider a treatment `x` and outcome `y` that share a common cause `z` (the
classic *fork*):

```@example fixing
scm_def = @bugs begin
    z ~ Normal(0, 1)              # confounder, drives both treatment and outcome
    x ~ Normal(z, 1)              # treatment assignment depends on z
    y ~ Normal(2 * x + z, 1)      # observed outcome
    y_rep ~ Normal(2 * x + z, 1)  # generated outcome under the same structural equation
end
scm = scm_def((; y = 3.0))
```

Here `z` opens a backdoor path between `x` and `y` (``x \leftarrow z \rightarrow y``):

- **Observing** `x = 1` (`condition(scm; x = 1.0)`) is informative about `z`, because `z`
  causes `x`. That shift in `z` then changes what we expect for `y` — part of the apparent
  effect of `x` on `y` flows through the confounder, not through the causal arrow `x → y`.
- **Intervening** `x = 1` (`fix(scm; x = 1.0)`) deletes the assignment `x ~ Normal(z, 1)`.
  Now `x` is set by us, not by `z`, so it carries no information about `z`. The observed `y`
  still contributes an interventional likelihood, while `y_rep` is left unobserved for
  posterior predictive draws under the intervention.

```@example fixing
intervened = fix(scm; x = 1.0)

(x_type     = JuliaBUGS.variable_type(intervened, @varname(x)),
 fixed_vars = JuliaBUGS.fixed_parameters(intervened),
 x_is_free  = @varname(x) in JuliaBUGS.parameters(intervened),       # false — x is set, not free
 z_sampled  = @varname(z) in JuliaBUGS.model_parameters(intervened), # true — z is still latent
 y_rep_type = JuliaBUGS.variable_type(intervened, @varname(y_rep)))
```

Sampling `intervened` and reading off `y_rep` with [`gen_chains`](generated_quantities.md)
yields posterior predictive draws from
``p(y_{\mathrm{rep}} \mid y = 3, \mathrm{do}(x = 1))``. Comparing the same query across a grid
of fixed values — `fix(scm; x = 0.0)`, `fix(scm; x = 1.0)`, … — traces out the causal effect of
the treatment, free of the confounding that `condition` would leave in.

## What fixing changes

Fixing assigns the [`VariableType`](@ref JuliaBUGS.VariableType) `FixedParameter` to each fixed
node and threads through every part of the model:

- **Parameter vector.** Fixed variables are dropped from
  [`model_parameters`](@ref JuliaBUGS.model_parameters) and from
  `LogDensityProblems.dimension`. They are *not* in the MCMC target.
- **Target density.** The fixed variable's own factor is not scored. Its descendants are scored
  using the fixed value.
- **Generated quantities.** Ancestors that only reached observations *through* the fixed
  variable now have no observed descendant, so they are reclassified as generated quantities and
  recovered by forward sampling instead of being sampled.
- **Evaluation modes.** Fixed values are honored in all three
  [evaluation modes](evaluation_modes.md): `UseGraph`, `UseGeneratedLogDensityFunction` (the
  generated function omits the fixed statements), and `UseAutoMarginalization` (a fixed discrete
  variable becomes a constant and is not summed over).

## Specifying variables and values

`fix` accepts the same flexible specifications as `condition`:

```@example fixing
fix(scm; x = 1.0)                              # keyword form
fix(scm, @varname(x) => 1.0)                   # a Pair
fix(scm, Dict(@varname(x) => 1.0))             # a Dict of VarName => value
fix(scm, [@varname(x)])                        # fix at the value currently in the model
fix(scm, @varname(x) => 1.0, @varname(z) => 0) # several specifications at once
nothing # hide
```

Passing a `VarName` without a value fixes it at its current value in the model's evaluation
environment. Array variables can be fixed wholesale; the assignment is expanded to the
individual elements (with a warning):

```@example fixing
arr_def = @bugs begin
    for i in 1:3
        x[i] ~ Normal(0, 1)
    end
    y ~ Normal(sum(x[:]), 1)
end
arr = arr_def((; y = 6.0))

arr_fixed = fix(arr, Dict(@varname(x) => [1.0, 2.0, 3.0]))
sort(JuliaBUGS.fixed_parameters(arr_fixed); by = string)
```

Only **unobserved stochastic** variables can be fixed. Fixing a deterministic node or an
observed variable raises an `ArgumentError`, and conditioning on a variable that is currently
fixed is likewise rejected.

## Unfixing

[`unfix`](@ref AbstractPPL.unfix) removes fixes and restores the original target
classification. Variables that had become generated quantities only because they were fixed
return to being model parameters, and `LogDensityProblems.dimension` grows back accordingly:

```@example fixing
unfix(chain_fixed)               # remove all fixes
unfix(chain_fixed, @varname(x))  # ... or a specific one by VarName
unfix(chain_fixed, :x)           # ... or by Symbol

LogDensityProblems.dimension(unfix(chain_fixed))  # back to 2: theta and x return to the target
```

## Performance: fixing in a loop

`fix` (and `unfix`) is **model surgery, not an evaluation step**. Each call rebuilds the graph
partition and invalidates the compiled log-density function and the marginalization cache, which
`set_evaluation_mode` then regenerates by `eval`-ing fresh code. On a small model, a
`fix` + regenerate round-trip in `UseGeneratedLogDensityFunction` mode measures ~10⁴× a bare
log-density evaluation. So keep `fix` out of hot loops — and note that its cost depends only on
*which* variables are fixed, never on their values.

**Varying the value of the same fixed variable** (e.g. tracing a causal effect across
`do(x = v)`): build the fixed model once, then update only its `evaluation_env`:

```@example fixing
base = fix(scm; x = 0.0)   # build the fixed structure once; x is the intervention target

map(-1.0:1.0:1.0) do v     # sweep do(x = v): only the value changes, structure is reused
    m = JuliaBUGS.BUGSModel(base;
        evaluation_env = JuliaBUGS.BangBang.setindex!!(base.evaluation_env, v, @varname(x)))
    LogDensityProblems.logdensity(m, [0.5])   # z held at 0.5 here just to show the values move
end
```

The `graph_evaluation_data`, the compiled function, and the marginalization cache are all reused;
only the stored value differs, so each step is essentially free. (Reaching into `evaluation_env`
is a low-level escape hatch today; a `set_fixed_values!` helper analogous to the existing
`set_observed_values!` would make this a one-liner.)

**Fixing different variables** across iterations: do *not* `unfix` then re-`fix` inside the loop
— that pays for two structural rebuilds (and, in the generated/marginalized modes, two
recompiles) every pass. The set of intervention targets is usually small, so pre-build one fixed
model per target outside the loop and reuse them:

```@example fixing
targets  = (@varname(x), @varname(z))
prebuilt = Dict(t => fix(scm, [t]) for t in targets)   # one fixed structure per target, built once

(dim_do_x = LogDensityProblems.dimension(prebuilt[@varname(x)]),
 dim_do_z = LogDensityProblems.dimension(prebuilt[@varname(z)]))
```

Within each pre-built model you can still value-swap as above. A note on modes: in `UseGraph`,
`fix` skips code generation (cheaper, but it still rebuilds the partition); in
`UseGeneratedLogDensityFunction` and `UseAutoMarginalization` it forces recompilation, so these
reuse patterns matter most there.

## API

```@docs
AbstractPPL.fix
AbstractPPL.unfix
JuliaBUGS.fixed_parameters
```

See the [Generated Quantities](generated_quantities.md) page for `model_parameters`,
`generated_quantities`, and `variable_type`.
