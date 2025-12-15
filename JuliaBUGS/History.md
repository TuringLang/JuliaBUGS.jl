# JuliaBUGS Changelog

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
