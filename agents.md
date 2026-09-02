# agents.md

Repository guidance for coding agents. User documentation is under `JuliaBUGS/docs/src/`.

## Project map

JuliaBUGS compiles `@bugs` programs and `@model` functions into graphs compatible with AbstractPPL, AbstractMCMC, and LogDensityProblems.

- `src/parser/`, `src/model_macro.jl`, `src/compiler_pass.jl`, and `src/graphs.jl`: front ends and graph construction.
- `src/model/bugsmodel.jl`, `src/model/evaluation.jl`, and `src/source_gen.jl`: model state and evaluation.
- `src/BUGSPrimitives/` and `ext/`: BUGS primitives and optional integrations.

## Tests and formatting

- Tests require `Pkg.test` with an explicit group or file; direct `test/runtests.jl` execution fails.
- Run the smallest target, for example: `julia --project=JuliaBUGS -e 'using Pkg; Pkg.test(; test_args=["log_density"])'`.
- Groups are in `test/runtests.jl`; `elementary` includes doctests and `parallel_sampling` needs threads.
- Use Julia-version-specific manifests (`Manifest-v{major}.{minor}.toml`), not `Manifest.toml`.
- Format with JuliaFormatter v1 using `format("JuliaBUGS"; verbose = true)`; discard unrelated changes.

## Julia engineering

- Preserve caller types with `zero`, `one`, and promotion; use concrete numeric types only when required.
- Accept abstract arrays, derive outputs with `similar`, and avoid eager slices or `Array` assumptions.
- Keep storage concrete with type parameters that support dispatch, storage, or an invariant.
- Prefer small dispatch-based protocols; isolate optional backends in extensions.
- Pass RNGs explicitly; test hot generated, AD, and log-density paths for inference and allocations.

## Semantic invariants

- Preserve BUGS parameterizations: `dnorm` takes precision and `dgamma` takes a rate, unlike Distributions.jl.
- BangBang `!!` methods may mutate or replace inputs; always reassign their results.
  `evaluation_env` stores model-space values and retained mutable state must not alias.
- Flattened parameters are transformed when `model.transformed` is true. Apply each
  log-Jacobian exactly once.
- `UseGraph`, `UseGeneratedLogDensityFunction`, and `UseAutoMarginalization` must agree on
  the target density. Generated evaluation must preserve graph semantics and errors.
- Every node has exactly one `VariableType`; only `ModelParameter` nodes enter the MCMC
  vector. Generated quantities are excluded and reconstructed in topological order.
- With no observations, stochastic nodes remain model parameters; fixed parameters are not scored.
- Auto-marginalization sums finite discrete parameters out. Verify changes to its order or
  frontier cache against explicit enumeration on a minimal model.
- Conditioning, fixing, or graph changes must invalidate dependent classification,
  parameter-layout, source-generation, and marginalization data.
- Each Gibbs block targets its full conditional given the latest values of all other blocks,
  including updates earlier in the same sweep. This constrains the target, not the proposal.
- Prefer direct draws from tractable full conditionals. `EnumeratedSampler` handles finite
  discrete blocks; add exact kernels for other recognized families, such as Normal, rather
  than using generic Metropolis-Hastings or slice transitions.
- Preserve types, shapes, and absent statistics through flat vectors, `ParamsWithStats`, MCMCChains, and FlexiChains.

## Front ends and review

- BUGS strings support `model { ... }`, `<-`, left-hand-side link functions, dotted names,
  truncation, and censoring. Both `@bugs` forms accept only registered primitives.
- `@model` runs in the caller's module and may use ordinary Julia functions. Preserve macro
  hygiene, caller scope, loop indexing, missing observations, and no-observation models.
- Keep AD work in narrow extension boundaries. Gradient samplers require an explicitly
  loaded backend; do not compile ReverseDiff tapes for parameter-dependent control flow.
- Sampler integrations implement `transition_params_and_stats`; shared conversion belongs in
  `bundle_transitions` and `gen_chains`.
- Add the smallest regression test and cover each affected front end, evaluation mode,
  output format, or backend. Preserve caller numeric and array types unless impossible.
- Test round trips after changes to flattening, reconstruction, serialization, or output.
  Check extension dependencies, benchmark hot paths, and document user-facing API.
