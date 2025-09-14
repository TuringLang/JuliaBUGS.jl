# AutoMarginalizationExperiments

A lightweight experiment harness (as a package) to showcase finite‑support discrete auto‑marginalization in JuliaBUGS combined with HMC.

Important: Auto-marginalization is on the current JuliaBUGS branch, not the latest release. Develop JuliaBUGS into this environment first:

```
julia --project=experiments/AutoMarginalizationExperiments -e 'using Pkg; Pkg.develop(path="JuliaBUGS"); Pkg.instantiate()'
```

Then try a quick run:

```
julia --project=experiments/AutoMarginalizationExperiments -e 'using Pkg; Pkg.instantiate()'
julia --project=experiments/AutoMarginalizationExperiments -e 'using AutoMarginalizationExperiments; AutoMarginalizationExperiments.run_gmm_autmarg_nuts(2000, 3)'
```

Goals (aligned with experiments/plan.md):
- Exactness/gradient checks on small models (GMM/HMM).
- Scaling vs weighted frontier width and order selection.
- ODE + finite discrete noise (PK Theoph) with reuse ablations.
- Single changepoint over a finite grid.
- “Must‑have” demos: GMM and HMM with NUTS on the marginalized target.

Folders:
- `src/` — package modules: metrics, ordering helpers, synthetic GMM/HMM, NUTS harness.
- Future: `scripts/` for CLI drivers and CSV logging; `pk_theoph/`, `changepoint_step/` subfolders.
