# Auto‑Marginalization Experiments — TODO

This checklist mirrors `experiments/plan.md` and what’s already in the repo. It focuses on finite‑support discrete latents (Bernoulli, Binomial, Categorical, DiscreteUniform, Beta‑Binomial, Hypergeometric) combined with heavy but pure deterministics, and HMC on the marginalized continuous target.

Existing in this folder
- [x] `benchmark_autmarg_logdensity.jl` — GMM and HMM logdensity (no gradients) under `UseAutoMarginalization`, interleaved order, optional CSV, basic correctness check for HMM at small T.
- [x] `stagnant_auto_marginalization.jl` — Stagnant example; supports original continuous model and discrete‑k variant; `REPARAM=true|false` toggle; runs under the test project; short NUTS/Gibbs smoke tests.
- [x] Notes/docs: `auto_marginalization_evaluation.md`, `auto_marginalization_report.md`.
- [x] Outputs: `results/`, `plots/`, `out_*.txt` (baseline timings).

Section 1 — Exactness and gradient checks
- [x] GMM exactness script: `experiments/AutoMarginalizationExperiments/scripts/exactness_gmm.jl`
  - [x] Synthetic small GMM (K=2, N≈10), closed‑form marginalized value/gradient vs `UseAutoMarginalization` + AD.
  - [x] Prints value/grad diffs (≈1e-14) — passes tolerance.
- [ ] HMM exactness script (`scripts/exactness_hmm.jl`):
  - [ ] Small HMM (S=2, T≈5), forward DP vs `UseAutoMarginalization` value; add gradients if μ/σ are continuous.

Section 2 — Scaling law vs weighted frontier width
- [ ] Create `experiments/scaling/` driver to sweep graph families and orders:
  - [ ] Families: chains/HMMs (width≈1), ladders (≈2), small grids (w grows with min dim).
  - [ ] Mixed domain sizes {2,4,10}; interleave light/heavy deterministics.
  - [ ] Orders: heuristic (min‑fill/min‑degree on moralized skeleton), random, adversarial.
  - [ ] Log predicted widths W(π), W⁺(π), measured peak memo size, fan‑out per `logsumexp`, wall‑clock, memory.
  - [ ] CSV output + small plotting helper (store in `plots/`).
- [x] Utility: metrics — added `experiments/AutoMarginalizationExperiments/src/metrics.jl`:
  - [x] CallCounter and `@counted` macro (hookable from ODE demos).

Section 3 — ODE model with discrete noise (PK Theoph)
- [ ] `experiments/pk_theoph/run.jl`:
  - [ ] Load Theoph via `RDatasets`.
  - [ ] One‑compartment oral absorption ODE (e.g., parameters c = (k_a,k_e,V)); solve with OrdinaryDiffEq, AD‑compatible sensitivities.
  - [ ] For each observation, Bernoulli indicator zᵢ ∈ {tight,fat} toggles noise scale; auto‑marg over all zᵢ.
  - [ ] “Good schedule” (reuse ODE once) vs “bad schedule” (recompute inside loop) ablation; instrument ODE solve counts using `metrics.jl`.
  - [ ] HMC on c and noise scales; report ESS/s, acceptance, per‑eval ODE solves.
  - [ ] CSV + concise summary print.

Section 4 — Single changepoint (finite grid)
- [ ] `experiments/changepoint_step/run.jl`:
  - [ ] Synthetic yₜ with μₜ = u₁ + u₂·step(t−s), s ∈ {2..N−1} finite grid, Normal noise.
  - [ ] Auto‑marg over s; expose posterior over s (softmax weights of internal logsumexp).
  - [ ] Compare with Gibbs on s; HMC on (u₁,u₂,τ); report ESS/s and trace sanity.

Section 5 — Order selection ablation
- [x] Add ordering ablation script: `experiments/AutoMarginalizationExperiments/scripts/ordering_ablation.jl`
  - [x] Compare default vs interleaved order on HMM; logs time and peak discrete frontier; equality of logp.
- [ ] Implement heuristic orderers (min‑fill/min‑degree), plus random and adversarial.
- [ ] Run on ladder/grid synthetic to demonstrate width effects.
- [ ] Extend to ESS/s when gradients exist (AD‑wrapped models).

Section 6 — Optional: circuit vs runtime VE
- [ ] (Optional) Add a small categorical‑emission HMM to compare compile time/per‑eval/per‑memory vs runtime VE (no heavy deterministics).

GMM & HMM “must‑have” demos
- [x] Harness functions in package: `run_gmm_autmarg_nuts`, `run_hmm_autmarg_nuts` (programmatic).
- [ ] CLI drivers + CSV logging for sweeps:
  - [ ] GMM (K=3, N sweep 1e3→5e4) with label‑invariance check; ESS/s and time vs N.
  - [ ] HMM (S=3, T sweep 200→2000), Gaussian emissions; ESS/s and time vs T.

Tooling & reproducibility
- [x] Package wrapper with Project.toml; dev‑script for JuliaBUGS (`scripts/setup.jl`).
- [ ] Standardize CLI flags across scripts (WARMUP, REPS, SEED, CSV_OUT, SAVE_DIR, REPARAM, ORDER).
- [ ] Seed handling and deterministic RNG usage (propagate in drivers).
- [ ] README snippets per subfolder; link to `plan.md`.
- [ ] Pin plotting/CSV deps and emit CSVs for figures.

Nice‑to‑have / future
- [ ] PK regimen‑class (finite Categorical) as a second ODE case.
- [ ] Occupancy model (finite Bernoulli occupancy) as a hierarchical example.

Immediate next actions (suggested)
1) Add `exactness/` GMM script and `utils/metrics.jl` (low effort, unlocks instrumentation for ODE work).
2) Scaffold `pk_theoph/` with an ODE that runs under `--project=JuliaBUGS/test`; print ODE‑solve counters.
3) Extend GMM/HMM benchmark with orderer hooks (even a simple min‑degree first), start logging width and memo peak.
