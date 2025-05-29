

# Model Layer – Design Overview
This document describes how the *model layer* of **JuliaBUGS** is organised.  
It explains which objects live in `src/model/`, what each object is
responsible for, and how evaluation of a probabilistic program flows from
user‑supplied data to a log‑density.

---
## 1. Purpose of the Model Layer
The model layer provides an **in‑memory representation** of a compiled BUGS
program together with the machinery required to

1. **Query** the graph (e.g. ask for parents, lengths, parameter order),
2. **Evaluate** the program under different contexts (log‑density,
   simulation, tempered log‑joint, etc.),
3. **Mutate** the program via conditioning/de‑conditioning while preserving
   provenance.

All higher‑level algorithms—HMC, SMC, Gibbs—build on top of these services.

---
## 2. Core Types

| Type | Role | Key Fields |
|------|------|------------|
| `AbstractBUGSModel` | Abstract super‑type to enable multiple concrete model implementations. | – |
| `BUGSModel` | Concrete implementation returned by `compile`. Holds both **static metadata** and **current variable values**. | `g`, `flattened_graph_node_data`, `evaluation_env`, `parameters`, `evaluation_mode`, … |
| `FlattenedGraphNodeData` | Cache of per‑node metadata laid out in *struct‑of‑arrays* form for fast indexed access during evaluation. | `sorted_nodes`, `is_stochastic_vals`, `node_function_vals`, … |
| `EvaluationMode` (+ sub‑types) | Tags the strategy for computing the log‑density. |  |
| `DefaultContext`, `SamplingContext`, `LogDensityContext` | Light‑weight structs that steer `evaluate!!` without relying on keyword arguments. |  |

### 2.1  Transformed vs Original Space
Many samplers operate in an **unconstrained (“transformed”) space**.  
Each `BUGSModel` therefore stores *two* sets of lengths:

* `untransformed_param_length` and `untransformed_var_lengths`
* `transformed_param_length`   and `transformed_var_lengths`

The boolean flag `transformed` selects which set is currently active.

---
## 3. Evaluation Pipeline

```mermaid
graph TD
    A[flattened_values] -->|LogDensityContext| E(evaluate!!)
    B[RNG]            -->|SamplingContext|   E
    C[evaluation_env] -->|DefaultContext|   E
    E --> F{for vn in sorted_nodes}
    F -->|deterministic| G[node_function(...)]
    F -->|stochastic|   H[dist = node_function(...)]
    H --> I{observed ?}
    I -->|yes|  J[loglikelihood += logpdf]
    I -->|no|   K[value ← encode/decode]
    K --> L[logprior += logpdf (+ jac)]
    G --> M[update env]
    J --> M
    L --> M
```

* The *driver* is `AbstractPPL.evaluate!!(model, ctx, …)`.
* Fast access to per‑node flags is provided by **indexing into
  `FlattenedGraphNodeData`**—there are **no graph look‑ups in hot loops**.
* The two evaluation strategies are selected by `evaluation_mode`:
  * **`UseGraph`** – interpret the graph each time.
  * **`UseGeneratedLogDensityFunction`** – call a
    compile‑time‑generated function that hard‑codes the graph logic.

### 3.1  Tempered Evaluation
`_tempered_evaluate!!` is a thin wrapper around the main loop that allows
the likelihood term to be multiplied by an arbitrary temperature
(used by AIS and tempering samplers).

---
## 4. Mutating a Model

| Operation | Result |
|-----------|--------|
| `condition(model, values)` | Returns a *new* `BUGSModel` where selected stochastic nodes become observed. |
| `decondition(model, vars)` | Reverts observation so the variables are treated as parameters again. |
| `settrans(model, flag)`    | Toggles between original and transformed parameter spaces. |
| `create_sub_model(model, params, vars)` | Materialises a sub‑graph that contains exactly the requested parameters and their Markov blanket. |

Each mutation **preserves** a pointer to the originating `base_model` so that
provenance is never lost.

---
## 5. Typical Workflow

```julia
desc = compile(my_model_definition, data)
rng  = Random.default_rng()

# ‑‑ draw a prior sample
env, logp = evaluate!!(rng, desc)           # SamplingContext

# ‑‑ compute log‑density at a parameter vector
θ   = getparams(desc)
_, ℓ = evaluate!!(desc, LogDensityContext(), θ)
```

---
## 6. Extensibility Notes
* **Additional evaluation modes** can be introduced by sub‑typing
  `EvaluationMode` and extending `evaluate!!`.
* The `FlattenedGraphNodeData` constructor is the single choke‑point for new
  per‑node metadata—extend it once and every evaluation path benefits.
* The model is designed to be **thread‑safe**: all immutable data live in the
  shared `BUGSModel`; per‑chain state is cloned via `deepcopy(evaluation_env)`.

---
*Last updated: 29 May 2025 (Europe/London)*