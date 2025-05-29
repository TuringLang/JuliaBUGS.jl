

# Refactor Plan – Splitting `BUGSModel`

*Last updated: 29 May 2025 (Europe/London)*

---
## 1. Goals
| Axis | Target |
|------|--------|
| **Performance** | Reduce log‑density evaluation time by ≥ 30 % on the Stan benchmarks suite; cut compilation latency (method specialisations) by ≥ 40 %. |
| **Memory** | Share immutable graph metadata between chains; decrease per‑chain footprint to \< 10 KB. |
| **Maintainability** | Encapsulate *what the model is* vs *what the evaluator is doing now* in two clearly‑named types. |
| **Extensibility** | Allow new evaluation back‑ends (e.g. GPU kernels) without touching the immutable description layer. |

---
## 2. Target Architecture

```text
┌──────────────────────┐          ┌─────────────────────┐
│ BUGSDescription{…}   │◄─────────┤ BUGSEvaluator{…}    │
│  • g : BUGSGraph     │ 1  (has) │  • env : NamedTuple │
│  • flat : meta-cache │──────────┤  • mode : EvalMode  │
│  • param_meta        │          │  • transformed?     │
└──────────────────────┘          └─────────────────────┘
```

* **`BUGSDescription`** – immutable, shareable, serialisable.
* **`BUGSEvaluator`** – per‑chain runtime state; cheap to clone.

---
## 3. Work Packages

| ID | Deliverable | Description | Owner | ETA |
|----|-------------|-------------|-------|-----|
| **WP‑0** | *Design freeze* | Finalise field layout & APIs; migrate docstrings. | ☑ *done* | 29 May |
| **WP‑1** | Skeleton types | Land empty structs + constructors; feature‑flag off by default. | Sun XD | 02 Jun |
| **WP‑2** | Metadata move | Shift graph, param maps, lengths into `BUGSDescription`; add delegation helpers. | Sun XD | 05 Jun |
| **WP‑3** | Evaluation refactor | Rewrite `evaluate!!`, `_tempered_evaluate!!`, `getparams` to accept `(desc, eval)`. | Sun XD | 10 Jun |
| **WP‑4** | Mutations layer | Re‑implement `condition`, `decondition`, `create_sub_model` to return new descriptions when necessary. | Sun XD | 15 Jun |
| **WP‑5** | Deprecation shim | Provide `BUGSModel` thin wrapper that internally builds `(desc, eval)`; emit `@warn` on construction. | Sun XD | 20 Jun |
| **WP‑6** | Benchmarks & docs | Revise benchmarks, update README & tutorials, remove shim in `v0.11`. | Sun XD | 25 Jun |

---
## 4. Migration Strategy

1. **Dual‑path execution** during WP‑1‒WP‑5: old `BUGSModel` APIs forward to new code so downstream samplers remain unaffected.
2. **Semantic parity tests**: Golden‑file log‑densities at 1e‑10 tolerance for 30 random models.
3. **Progressive PRs**: keep diff < 1 kLoC each; CI must stay green.

---
## 5. Acceptance Criteria

* All existing unit + integration tests pass.
* `median(bench/new)/median(bench/old) ≤ 0.70` for evaluation speed.
* `Base.summarysize(evaluator) ≤ 10_240` bytes.
* No `@code_warntype` red highlights in hot paths.

---
## 6. Risk & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Type instability in `env` | Slowdowns cancel perf gains | Emit concrete `NamedTuple` type at compile time. |
| Downstream API breakage | User frustration | Deprecation shim + changelog w/ recipes. |
| Increased compile time for generated log‑density | Neutralises runtime improvements | Gating flag keeps generated path optional; profile each PR. |

---
## 7. Stakeholders
* **Lead**: Sun XD (@sunxd)
* **Reviewers**: TuringLang maintainers, ProbProg WG
* **Consumers**: `Turing.jl`, `AbstractMCMC.jl` ecosystem

---
Happy refactoring! :sparkles: