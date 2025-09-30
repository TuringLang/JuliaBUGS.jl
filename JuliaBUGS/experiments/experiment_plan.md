# Experiment Plan: Auto-Marginalization

Experiments validating automatic marginalization of discrete latent variables in JuliaBUGS.

## 1. Correctness

Validates marginalized log-probability against analytical references.

```bash
# HMM
AM_SWEEP_SEEDS=1,2,3 AM_SWEEP_K=2,4,8,16 AM_SWEEP_T=50,100,200,400 \
  julia --project=JuliaBUGS/experiments scripts/hmm_correctness_sweep.jl

# GMM
AG_SWEEP_SEEDS=1,2,3 AG_SWEEP_K=2,4,8 AG_SWEEP_N=100,500,1000,5000 \
  julia --project=JuliaBUGS/experiments scripts/gmm_correctness_sweep.jl

# HDP-HMM (sticky, κ=0)
AHDPC_SEEDS=1,2 AHDPC_K=5,10,20 AHDPC_T=50,100,200,400 AHDPC_KAPPA=0.0 \
  julia --project=JuliaBUGS/experiments scripts/hdphmm_correctness.jl

# HDP-HMM (sticky, κ=5)
AHDPC_SEEDS=1,2 AHDPC_K=5,10,20 AHDPC_T=50,100,200,400 AHDPC_KAPPA=5.0 \
  julia --project=JuliaBUGS/experiments scripts/hdphmm_correctness.jl
```

## 2. Gradients

Validates automatic differentiation against finite differences.

```bash
# HMM
AGC_SWEEP_SEEDS=1,2,3 AGC_SWEEP_K=2,4,8 AGC_SWEEP_T=50,100,200 \
  julia --project=JuliaBUGS/experiments scripts/hmm_gradient_check.jl

# GMM
AGG_SWEEP_SEEDS=1,2,3 AGG_SWEEP_K=2,4,8 AGG_SWEEP_N=200,500,1000 \
  julia --project=JuliaBUGS/experiments scripts/gmm_gradient_check.jl

# HDP-HMM (sticky, κ=0)
AHDPG_SWEEP_SEEDS=1,2 AHDPG_SWEEP_K=5,10,20 AHDPG_SWEEP_T=100,200 AHDPG_KAPPA=0.0 \
  julia --project=JuliaBUGS/experiments scripts/hdphmm_gradient_check.jl

# HDP-HMM (sticky, κ=5)
AHDPG_SWEEP_SEEDS=1,2 AHDPG_SWEEP_K=5,10,20 AHDPG_SWEEP_T=100,200 AHDPG_KAPPA=5.0 \
  julia --project=JuliaBUGS/experiments scripts/hdphmm_gradient_check.jl
```

## 3. Scaling

Benchmarks runtime vs problem size.

```bash
# HMM
AS_SWEEP_K=8,16,32,64,128,256,512 AS_SWEEP_T=50,100,200,400,800 \
  julia --project=JuliaBUGS/experiments scripts/hmm_scaling_bench.jl
```

## 4. Variable Ordering: FHMM

Compares elimination orders (interleaved, states_then_y, min_fill, min_degree).

```bash
# Small configs with timing
AFH_C=2 AFH_K=2 AFH_T=5 AFH_MODE=timed AFH_ORDERS=interleaved,states_then_y \
  julia --project=JuliaBUGS/experiments scripts/fhmm_order_comparison.jl
AFH_C=2 AFH_K=4 AFH_T=10 AFH_MODE=timed AFH_ORDERS=interleaved,states_then_y \
  julia --project=JuliaBUGS/experiments scripts/fhmm_order_comparison.jl

# Larger configs (frontier only)
AFH_C=2 AFH_K=4 AFH_T=50 AFH_MODE=frontier AFH_ORDERS=interleaved,states_then_y,min_fill,min_degree \
  julia --project=JuliaBUGS/experiments scripts/fhmm_order_comparison.jl
AFH_C=3 AFH_K=4 AFH_T=50 AFH_MODE=frontier AFH_ORDERS=interleaved,states_then_y,min_fill,min_degree \
  julia --project=JuliaBUGS/experiments scripts/fhmm_order_comparison.jl
AFH_C=4 AFH_K=4 AFH_T=50 AFH_MODE=frontier AFH_ORDERS=interleaved,states_then_y,min_fill,min_degree \
  julia --project=JuliaBUGS/experiments scripts/fhmm_order_comparison.jl
```

## 5. Variable Ordering: HMT

Compares tree traversal orders (dfs, bfs, random_dfs, min_fill, min_degree).

```bash
# Varying depth
AHMT_B=2 AHMT_K=4 AHMT_DEPTH=4 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl
AHMT_B=2 AHMT_K=4 AHMT_DEPTH=6 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl
AHMT_B=2 AHMT_K=4 AHMT_DEPTH=8 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl
AHMT_B=2 AHMT_K=4 AHMT_DEPTH=10 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl

# Varying branching and states
AHMT_B=2 AHMT_K=2 AHMT_DEPTH=6 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl
AHMT_B=3 AHMT_K=2 AHMT_DEPTH=6 AHMT_MODE=frontier \
  julia --project=JuliaBUGS/experiments scripts/hmt_order_comparison.jl
```

## Notes

- **Ordering matters**: Good elimination orders (e.g., interleaved for HMMs) keep frontier width ≈ O(1), achieving O(K·T) cost. Bad orders (e.g., states-first) explode to O(K^T).
- **Heuristics**: Min-fill and min-degree with randomized tie-breaking (3 restarts) find good orders for arbitrary graphical models.
- **HDP-HMM**: Both correctness and gradient scripts use the sticky HDP-HMM formulation with kappa (κ) parameter. Set AHDPC_KAPPA/AHDPG_KAPPA to control sticky self-transition bias. κ=0 is standard HDP-HMM, κ>0 adds self-transition preference.
- **Output**: All scripts write CSV to stdout. Redirect as needed: `> results/output.csv`