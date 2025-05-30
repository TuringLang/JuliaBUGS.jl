# JuliaBUGS – Incremental Model-Layer Refactor Plan

This document captures **why** and **how** we will evolve the current `src/model`
implementation without adopting the full rewrite that lives in
`src/refactored_model`. The goal is to harvest the highest-value ideas from the
prototype while keeping the public API and the majority of the codebase
stable.

──────────────────────────────────────────────────────────────────────────────
## 0. High-level Goals

1. **Remove hidden performance bottlenecks** (unnecessary deep copies, flag
   branches in hot loops).
2. **Decouple concerns** that are currently conflated in `BUGSModel`:
   • model description vs per-chain state,
   • parameter vector order vs graph traversal order.
3. **Keep the surface API intact** so that existing examples, tests and user
   code continue to run unmodified.

──────────────────────────────────────────────────────────────────────────────
## 1. Non-Goals

* We will **not** introduce the type-parameterised `Transformed / Untransformed`
  evaluators of the prototype.
* We will **not** remove specialised `evaluate!!` variants; alignment with the
  original DynamicPPL interface takes precedence over maximal de-duplication.
* We will **not** change the generated-function pathway in this phase.

──────────────────────────────────────────────────────────────────────────────
## 2. Deliverables and Milestones

| Milestone | Description | PR Label |
|-----------|-------------|---------|
| M1 | `EvaluationEnvironment` wrapper + `smart_copy` integrated into all evaluation and initialisation code paths. | `model-perf` |
| M2 | Parameter order decoupled from `sorted_nodes`; new fast lookup table `param_index`. | `model-params` |
| M3 | Extract immutable `ModelDescription` sub-struct inside `BUGSModel`. | `model-clean` |
| M4 | Move `is_transformed(model)` check out of the inner evaluation loop. | `model-hot-loop` |
| M5 | Benchmarks & regression tests covering prior sampling, log-density and conditioning/de-conditioning. | `model-tests` |

──────────────────────────────────────────────────────────────────────────────
## 3. Detailed Task Breakdown

### 3.1 Milestone M1 – Smart copy of the evaluation environment

1. **Add new file** `src/model/evaluation_environment.jl` containing:
   ```julia
   struct EvaluationEnvironment{names,T<:NamedTuple{names}}
       values  :: T
       is_data :: NamedTuple{names, NTuple{N,Bool}} where {N}
   end
   ```
2. Implement `smart_copy(env)` that leaves immutable data arrays untouched and
   copies everything else.
3. Replace every `deepcopy(model.evaluation_env)` with `smart_copy(...)`
   (search in `evaluation.jl`, `initialize!.jl`, `model_operations.jl`).
4. Add unit tests that compare outputs of `deepcopy` & `smart_copy` for mixed
   data/parameter environments.

### 3.2 Milestone M2 – Decouple `parameters` from `sorted_nodes`

1. Ensure constructor keeps the current external order (passed down from
   `compile`).  **Do not** re-order to match topological sort.
2. Add `param_index::Dict{VarName,Int}` for O(1) slice lookup.
3. Update:
   * `getparams` – iterate over `parameters` to collect values.
   * `_tempered_evaluate!!` – **still** iterate over `sorted_nodes` for graph
     walking but use `param_index` when slicing the parameter vector.
   * `initialize!(model, vec)` – unpack using `param_index`.
4. Remove any assertion that checks `parameters[i] == sorted_nodes[...]`.

### 3.3 Milestone M3 – Extract `ModelDescription`

1. Define:
   ```julia
   struct ModelDescription{TNF,TV,F}
       g::BUGSGraph
       flattened_graph_node_data::FlattenedGraphNodeData{TNF,TV}
       parameters::Vector{VarName}
       log_density_function::F
       model_def::Expr
       data::NamedTuple
   end
   ```
2. Replace duplicate fields in `BUGSModel` with single `desc::ModelDescription`.
3. Update field access across all source files (`desc.g`, `desc.parameters`, …).

### 3.4 Milestone M4 – Hot-loop simplification

1. Add inline function `is_transformed(model)::Bool = model.transformed`.
2. At the start of `_tempered_evaluate!!` cache:
   ```julia
   transformed = is_transformed(model)
   var_lengths = transformed ? model.transformed_var_lengths : model.untransformed_var_lengths
   ```
   Use `transformed` flag inside the loop **instead of testing the field each
   iteration**.

### 3.5 Milestone M5 – Benchmarks & tests

1. Extend existing `test/model/evaluation.jl` to include:
   * Equality of log-densities pre-/post-M2 for several compiled models.
   * Memory-allocation checks for `evaluate!!(rng, model)` (expect fewer
     allocations after M1).
2. Run `benchmark/juliabugs.jl` before and after each milestone; keep numbers
   in the PR description.

──────────────────────────────────────────────────────────────────────────────
## 4. Risk Management

* **Silent changes in parameter order** – catch via round-trip tests: pack with
  `getparams`, unpack with `initialize!`, compare environment.
* **Thread safety of EvaluationEnvironment** – maintain strict immutability of
  `values`, only replace the entire NamedTuple on mutation (no interior
  mutability).
* **Performance regression in HMC** – run NUTS benchmark after each milestone.

──────────────────────────────────────────────────────────────────────────────
## 5. Future Ideas (not scheduled)

* Switch to type-level `Transformed/Untransformed` evaluators once the above
  groundwork lands.
* Re-open `src/refactored_model` for a potential v1.0 rewrite after gaining
  confidence with incremental improvements.

──────────────────────────────────────────────────────────────────────────────
*Last updated: 29 May 2025*
