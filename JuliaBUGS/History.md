# JuliaBUGS Changelog

## 0.15.0

### Highlights

- **Generated quantities (#501).** Every node now carries an explicit `VariableType`: `Observation`, `ModelParameter`, `TransformedParameter`, `GeneratedQuantity`, or `FixedParameter`. A *generated quantity* is an unobserved node (stochastic or deterministic) with no observed descendants, so it lies outside the log-density target. Generated quantities are excluded from the log density in all three evaluation modes (`UseGraph`, `UseGeneratedLogDensityFunction`, `UseAutoMarginalization`) and recovered after sampling by forward simulation instead of being sampled by MCMC. Under auto-marginalization, a generated quantity that depends on a marginalized discrete latent first recovers that latent from its conditional posterior `p(z | θ, y)`. `gen_chains` applies this automatically, so reported generated quantities are genuine posterior(-predictive) draws.

- **AbstractPPL `fix`/`unfix`.** `BUGSModel` now implements `AbstractPPL.fix` and `AbstractPPL.unfix`. Fixed stochastic variables are interventions: descendants see the fixed value, but the fixed variable's distribution is not scored and the variable is removed from the parameter vector. This is supported in graph, generated log-density, and auto-marginalized evaluation modes.

- **New functions**, exported from the `JuliaBUGS.Model` submodule (like the existing `parameters`), so reachable as `JuliaBUGS.model_parameters` rather than via `using JuliaBUGS`: `model_parameters`, `generated_quantities`, `fixed_parameters`, `variable_type`, and the `VariableType` enum with its instances. `forward_sample_generated_quantities!!` is unexported, available as `JuliaBUGS.Model.forward_sample_generated_quantities!!`.

- **FlexiChains support** (#483): Sampling can now collect results into a [`FlexiChains.FlexiChain{VarName}`](https://github.com/penelopeysm/FlexiChains.jl) by passing `chain_type=VNChain` (after `using FlexiChains`). Chains are keyed by `VarName`, so array-valued variables are stored whole instead of being flattened into scalar columns, and sampler statistics are stored as `FlexiChains.Extra` entries. This is the chain format the rest of the TuringLang ecosystem is moving to (Turing 0.45 uses it by default); the docs now use it in examples. `MCMCChains` remains fully supported via `chain_type=MCMCChains.Chains`, and a `FlexiChain` can be converted with `MCMCChains.Chains(chain)`.

- **Slice sampling** ([SliceSampling.jl](https://github.com/TuringLang/SliceSampling.jl)): slice samplers can now sample `BUGSModel`s once `using SliceSampling`. They work standalone — pass a sampler such as `SliceSteppingOut` directly to `AbstractMCMC.sample` — and as component samplers inside `JuliaBUGS.Gibbs` (in the `sampler_map`), where each single-site conditional is univariate. Being derivative-free, they need no AD backend. Both `MCMCChains` (`chain_type=Chains`) and `FlexiChains` (`chain_type=VNChain`) outputs are supported, with sampler statistics (`lp`, `num_proposals`) recorded. Shipped as three package extensions mirroring the existing HMC/MH split. See the *Slice Sampling* page in the docs.

- **Callable `@bugs` (#383).** `@bugs` and `@bugs"..."` now return a callable `BUGSModelDef` instead of a bare `Expr`, so a model builds in one step — `model = (@bugs begin … end)(data)` — mirroring `@model`. This is primarily a **syntax/ergonomics change**: `compile` still accepts the wrapper (and raw `Expr`s), so existing `compile(@bugs(...), data)` code, serialization, and source generation keep working unchanged, and the underlying AST stays available via the `.model_def` field. It makes `compile` an implementation detail rather than a required step. The callable also takes an optional second positional argument of initial parameter values — `model_def(data, inits)`, mirroring `compile(model_def, data, initial_params)` — so supplying starting values (for instance when random draws from vague priors would be out of support) needs no `compile` call either.

### Breaking Changes

- Unobserved stochastic nodes with **no observed descendants** (e.g. posterior-predictive draws, or priors unused by any likelihood) are now generated quantities: excluded from `model_parameters`, the parameter vector, and `LogDensityProblems.dimension`, and forward-sampled in post-processing instead of sampled by MCMC/Gibbs. The joint distribution is unchanged.
- `parameters(model)` (all unobserved stochastic nodes) and `model_parameters(model)` (the MCMC target) can now differ, and `dimension` follows `model_parameters`. Use `LogDensityProblems.dimension(model)` (or `length(model_parameters(model))`) where you previously relied on `length(parameters(model))` as the parameter-vector length.
- `Gibbs` sampler maps that reference a reclassified variable now error, since it is no longer in `model_parameters`.
- The return type of `@bugs` / `@bugs"..."` changed from `Expr` to `BUGSModelDef` (#383). This is a low-impact, largely syntactic change (see the *Callable `@bugs`* highlight): the usual `compile(@bugs(...), data)` path, serialization, and source generation are unaffected. Only code that introspected the macro result *as* an `Expr` (e.g. `(@bugs ...).args`) must switch to the `.model_def` field.

## 0.14.1

### Highlights

- **`to_distribution(model::BUGSModel)`** (#459, closes #27): Wrap a compiled BUGS model as a `Distributions.Distribution` with variate type `NamedTupleVariate{names}`, where `names` are the unique parameter symbols. `rand` performs ancestral sampling and returns a `NamedTuple`; `logpdf` evaluates the joint log density in the original (constrained) parameter space at the supplied `NamedTuple`. This makes BUGS models composable inside other PPLs that consume `Distribution` objects.

- **`of` type system moved to AbstractPPL.** The `of`/`@of` type-specification system now lives in [AbstractPPL](https://github.com/TuringLang/AbstractPPL.jl/pull/168) and is re-exported from JuliaBUGS. The public API is unchanged — `of`, `@of`, and the `of(::BUGSModel)` convenience method continue to work as before — so this is a non-breaking change. JuliaBUGS now requires `AbstractPPL ≥ 0.15.3`.

### Improvements

- Widened dependency compat bounds (#471): `Distributions = "0.25.117"`, `LogExpFunctions = "0.3, 1.0"`, and `OrderedCollections = "1, 2.0"`.

### Internal

- Replaced CompatHelper with Dependabot for dependency updates (#463) and bumped CI GitHub Actions versions.

## 0.14.0

### Highlights

- **Native AbstractPPL evaluator API for gradients** (#454, closes #449): `BUGSModelWithGradient` now prepares and computes gradients through `AbstractPPL.prepare` and `AbstractPPL.value_and_gradient!!` instead of calling `DifferentiationInterface` directly. This lets JuliaBUGS use AbstractPPL's native Mooncake extension.

- **Mooncake-first.** `AutoMooncake()` is now the recommended AD backend and works with all three evaluation modes: `UseGraph()`, `UseGeneratedLogDensityFunction()`, and `UseAutoMarginalization()`. Docs and the main tutorial default to it.

### Breaking Changes

- **`DifferentiationInterface` is no longer a JuliaBUGS dependency.** Users of DI-backed backends like `AutoReverseDiff` and `AutoForwardDiff` must now load `DifferentiationInterface` themselves alongside the concrete AD package, for example `using ADTypes, DifferentiationInterface, ReverseDiff`. For Mooncake, just `using ADTypes, Mooncake` is enough. For distributed sampling, the same packages must be loaded on every worker.

- **AbstractPPL compat bumped to `0.15`** for the new evaluator API.

- **`BUGSModelWithGradient.prep` field type changed** from a DifferentiationInterface prep object to an `AbstractPPL.Evaluators.Prepared`. Code that reaches into `.prep` directly needs to be updated.

### Improvements

- `smart_copy_evaluation_env` now preserves the `NamedTuple` type of `evaluation_env` and only deep-copies mutable fields, which fixes Mooncake reverse mode on the graph evaluator.
- `AutoMooncakeForward()` is auto-routed to `UseGeneratedLogDensityFunction()` mode when source generation is possible; a clear `ArgumentError` is raised otherwise.
- `Bijectors 0.16` is now allowed in compat.

## 0.13.0

### Breaking Changes

- Bumped AbstractPPL compat to `0.14` (#422).

## 0.12.3

- Fix serialization for `BUGSModel` and add round-trip tests (#435)
- `MetaGraphsNext` 0.8 is now allowed in compat (#425)

## 0.12.2

- Catch `DomainError` in `LogDensityProblems.logdensity` to prevent HMC crashes from leapfrog integration (#434)
- Fix math and inline LaTeX rendering on docs pages (#430)

## 0.12.1

- Added support for `AbstractMCMC.mcmc_callbacks`, including `TensorBoardLogger.jl` (#423). See the [callbacks docs](https://turinglang.org/AbstractMCMC.jl/stable/callbacks/#TensorBoard-Logging).

## 0.12.0

### Highlights

- **DifferentiationInterface.jl integration** (#397): Use `adtype` parameter in `compile()` to enable gradient-based inference via [ADTypes.jl](https://github.com/SciML/ADTypes.jl).
  - Example: `model = compile(model_def, data; adtype=AutoReverseDiff())`
  - Supports `AutoReverseDiff`, `AutoForwardDiff`, `AutoMooncake`

- **Auto-marginalization for discrete parameters** (#385): Automatically marginalize discrete latent variables to enable gradient-based inference on models with discrete parameters.
  - Example: `model = set_evaluation_mode(settrans(compile(model_def, data), true), UseAutoMarginalization())`
  - Supports models where discrete parameters have finite support (e.g., `Categorical`, `Bernoulli`)

- **On-demand log density function generation** (#416): Log density functions are now generated on-demand when `set_evaluation_mode(model, UseGeneratedLogDensityFunction())` is called, rather than at compile time. All models start with `UseGraph()` mode.

### Breaking Changes

- `LogDensityProblemsAD.ADgradient` is no longer supported. Use `compile(...; adtype=...)` or `BUGSModelWithGradient(model, adtype)` instead.
- The `skip_source_generation` parameter has been removed from `compile()` and `BUGSModel()`.

### Improvements

- Expanded support for generated log density functions via dependence vectors (#390)
- Julia 1.12 compatibility improvements (#404)

## 0.11.0

### Breaking Changes

- **Simplified sampling API** (#406): Replaced `sample_all` and `respect_observed` kwargs with `sample_observed` in `AbstractPPL.evaluate!!`.
  - Default behavior unchanged (samples latents, keeps observed fixed)
  - `sample_all=true, respect_observed=false` → `sample_observed=true`
  - Other uses → remove (now default)

## 0.10.5

- Add `respect_observed` kwarg to `evaluate_with_rng!!` to control whether observed values are resampled (#405)

## 0.10.4

- Add `skip_source_generation` option to `compile()` for serialization compatibility (#403)

## 0.10.2

- Fast conditioning API (#394): Add `regenerate_log_density=false` option to `condition()` for hot loops
  - New `set_observed_values!` for in-place value updates
  - New `regenerate_log_density_function` for explicit regeneration
- R interface via `rjuliabugs` package (#389)

## 0.10.1

Expose docs for changes in [v0.10.0](https://github.com/TuringLang/JuliaBUGS.jl/releases/tag/JuliaBUGS-v0.10.0)

## 0.10

This is a major overhaul since v0.9.0. It introduces a faster evaluation mode, a refactored Gibbs sampler API, a new conditioning workflow, and a Turing-like modeling macro along with an ergonomic type system for model parameters.

### Highlights

- New evaluation mode: generated log-density function
  - Add `UseGeneratedLogDensityFunction()` and `UseGraph()` evaluation modes; switch with `set_evaluation_mode(model, mode)`. Falls back to graph traversal when generation isn’t available.
  - Works in transformed (unconstrained) space only; call `settrans(model, true)` before enabling. If the model is untransformed, enabling the generated mode throws a helpful error.
  - Supported AD backends: Mooncake and Enzyme only, because the generated function mutates; other AD backends are not compatible with this mode for now.
  - Brings significant speedups on supported models; fixes cover conditioned models and discrete evaluation paths.
  - Related: #278, #276, #289, #279, #315, #318, #314.

- Refactored Gibbs sampler and samplers API
  - New `Gibbs` API supports mapping variable groups to samplers via `OrderedDict`, with automatic expansion of subsuming variables (e.g., `@varname(x)` covers `x[i]`).
  - Gradient-based samplers now require an explicit AD backend passed as a tuple `(sampler, ad_backend)` (from ADTypes); the previous default wrapper approach was removed.
  - `MHFromPrior` was renamed/replaced by a clearer `IndependentMH` single-site sampler; supports standalone use and within Gibbs via `gibbs_internal`.
  - Uses `AbstractMCMC.setparams!!` to keep stateful samplers in sync during Gibbs updates; includes multi-threaded sampling tests.
  - Related: #320, #329, #330, #332.

- Conditioning API overhaul (no subgraph creation)
  - `condition(model, ...)` now marks variables as observed in the same graph instead of creating a subgraph, and updates parameter sets accordingly. New `decondition` restores parameters and observation status.
  - Accepts `Dict{VarName,Any}`, `Vector{VarName}` (uses current values), or a `NamedTuple` for simple names; handles subsumption (e.g., `x` covers all `x[i]`) with diagnostics.
  - Related: #309, #314, #318, #313.

- New modeling APIs: `@model` macro and `of` types
  - `@model` macro creates a model-generating function from a function definition. The first argument destructures stochastic parameters `(; ...)` and may carry an `of` type annotation to validate structure and shapes.
  - `of` and `@of` define type-level parameter specs with bounds, symbolic dimensions, and constants (e.g., `@of(n=of(Int; constant=true), data=of(Array, n, 2))`). These integrate with `@model` and provide helpers like `zero(T)` and instance construction `T(; kwargs...)`.
  - Related: #291, #331.

### Breaking changes

- Gradient samplers must specify AD backend explicitly
  - Pass `(HMC(...), AutoForwardDiff())`, `(NUTS(...), AutoReverseDiff())`, or another `ADTypes` backend in the Gibbs map. The old default AD wrapper pattern was removed. (#330)

- Renamed/updated MH sampler
  - Replace `MHFromPrior()` with `IndependentMH()`. Update Gibbs sampler maps accordingly. (#329)

- Conditioning semantics and API
  - `condition` no longer constructs a subgraph; it mutates observation flags within a copy of the graph and returns a new `BUGSModel`. Use `decondition(model)` (or with specific variables) to restore. (#309, #314, #318)

- Primitive registration macro rename
  - The macro to register custom callables for `@bugs` is now `@bugs_primitive` (replacing the old name in code). Adjust any usage accordingly.

### New features

- Generated evaluation mode: `UseGeneratedLogDensityFunction()` with `set_evaluation_mode(model, ...)` and `settrans(model, ...)` guards. (#278, #315, #318)
- Turing-like `@model` macro that builds a compiled `BUGSModel` function; supports `of` type annotations on the destructured parameter arg. (#291)
- `of`/`@of` type system for parameter specs with constants, bounds, symbolic dims, and convenient constructors/utilities. (#331)
- `IndependentMH` sampler usable standalone or within Gibbs. (#329)
- `decondition(model[, vars])` to reverse conditioning. (#314)

### Improvements and fixes

- Model and evaluation
  - Fix and refine generated log-density for conditioned models; recursive handling of discrete computations; parameter sorting now includes only true model parameters. (#292, #289, #315, #318)
  - Refactor model internals into a `Model` module and move `logdensityproblems` integration there. (#306, #313)
  - Light refactors to `BUGSModel` and evaluation utilities. (#310, #314)

- Graphs and utilities
  - Improve `graphs.jl`; remove legacy graph code; clarify imports and macro names. (#304, #323, #354)

- Examples and docs
  - Add BUGSExamples Volume 3; update several example models and inter-op examples; README updates; clarify `dmnorm` usage notes. (#284, #277, #249, #369, #280)

- Test, CI, and infra
  - Restructure tests; enable experimental tests; add `test_args` support; improve coverage and docs workflows; new folder layout. (#317, #365, #348, #295, #372, #373, #368)

- Compatibility
  - Bump compat: AbstractPPL 0.11; AdvancedHMC [weakdeps] 0.7; JuliaSyntax 1; assorted package compat and Project.toml updates. (#282, #283, #287, #366, #367)

Usage notes and migration tips

- Enabling the generated evaluation mode
  ```julia
  model = compile(@bugs begin
      # ...
  end, data)
  model = settrans(model, true)  # generated mode requires transformed space
  model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
  # falls back to UseGraph() automatically if generation isn’t supported
  ```

- Gibbs with explicit AD backends for gradient samplers
  ```julia
  using ADTypes: AutoForwardDiff, AutoReverseDiff
  sampler_map = OrderedDict(
      @varname(μ) => (HMC(0.01, 10), AutoReverseDiff()),
      @varname(σ) => (NUTS(0.65), AutoForwardDiff()),
      @varname(k) => IndependentMH(),  # discrete or non-gradient
  )
  gibbs = Gibbs(model, sampler_map)
  ```

- Conditioning and deconditioning
  ```julia
  using JuliaBUGS.Model: condition, decondition
  m1 = condition(model, Dict(@varname(x[1]) => 1.0, @varname(x[2]) => 2.0))
  m2 = decondition(m1)  # restore to the unconditioned parameterization
  ```

- Defining models with `@model` and `of`
  ```julia
  RegressionParams = @of(
      y     = of(Array, 100),         # observed
      beta  = of(Array, 3),           # parameter
      sigma = of(Real, 0, nothing),   # parameter with lower bound
  )

  @model function regression((; y, beta, sigma)::RegressionParams, X, N)
      for i in 1:N
          mu[i] = X[i, :] ⋅ beta
          y[i] ~ dnorm(mu[i], sigma)
      end
      beta ~ dnorm(0, 0.001)
      sigma ~ dgamma(0.001, 0.001)
  end

  model = regression((; y = y_obs), X, N)
  ```

### Additional notes

- DoodleBUGS project (not part of this release): Substantial progress (Phase 1, code generation, data input, nested plates, exports, state persistence) and workflow isolation landed in this repo. These changes are present but out of scope for 0.10 and will be kept under a dedicated subfolder. See #339, #347, #357, #340, #341.

Thanks to everyone who contributed issues, PRs, reviews, and ideas across this cycle!
