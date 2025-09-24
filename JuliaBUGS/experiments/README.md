# Experiments Workspace

- Project path: `JuliaBUGS/experiments`
- Scripts live in `JuliaBUGS/experiments/scripts/`
- Shared helpers are in `JuliaBUGS/experiments/utils.jl`

## Running scripts

Always pass the experiments project to Julia so the correct environment loads:

```
julia --project=JuliaBUGS/experiments scripts/hmm_marginal_logp.jl
```

Most scripts accept environment variables to tweak configurations. The simple
HMM example supports:

- `AM_SEED` (default `1`) – RNG seed used for synthetic data.
- `AM_T` (default `50`) – length of the simulated sequence.

Batch sweep (`hmm_correctness_sweep.jl`):

- `AM_SWEEP_SEEDS` (default `1`) – comma-separated list of seeds.
- `AM_SWEEP_K` (default `2,4`) – comma-separated list of state counts.
- `AM_SWEEP_T` (default `50,200`) – comma-separated list of sequence lengths.

GMM sweep (`gmm_correctness_sweep.jl`):

- `AG_SWEEP_SEEDS` (default `1`) – comma-separated list of seeds.
- `AG_SWEEP_K` (default `2,4`) – comma-separated list of mixture counts.
- `AG_SWEEP_N` (default `100,1000`) – comma-separated list of observation counts.

HMM gradient check (`hmm_gradient_check.jl`):

- `AGC_SEED` (default `1`) – RNG seed for synthetic data.
- `AGC_K` (default `2`) – number of HMM states.
- `AGC_T` (default `50`) – length of the simulated sequence.
- `AGC_EPS` (default `1e-5`) – step size for central finite differences.
- `AGC_VERBOSE` (default `0`) – set `1` to print per-θ details.
- `AGC_SWEEP_SEEDS` – comma-separated list of seeds (overrides `AGC_SEED`).
- `AGC_SWEEP_K` – comma-separated list of state counts (overrides `AGC_K`).
- `AGC_SWEEP_T` – comma-separated list of sequence lengths (overrides `AGC_T`).

GMM gradient check (`gmm_gradient_check.jl`):

- `AGG_SEED` (default `1`) – RNG seed for synthetic data.
- `AGG_K` (default `2`) – number of mixture components.
- `AGG_N` (default `200`) – number of observations.
- `AGG_EPS` (default `1e-5`) – step size for central finite differences.
- `AGG_VERBOSE` (default `0`) – set `1` to print per-θ details.
- `AGG_SWEEP_SEEDS` – comma-separated list of seeds (overrides `AGG_SEED`).
- `AGG_SWEEP_K` – comma-separated list of mixture counts (overrides `AGG_K`).
- `AGG_SWEEP_N` – comma-separated list of observation counts (overrides `AGG_N`).

HMM scaling benchmark (`hmm_scaling_bench.jl`):

- `AS_SEED` (default `1`) – RNG seed. Use `AS_SWEEP_SEEDS` for a list.
- `AS_K` (default `2,4`) – number of states. Use `AS_SWEEP_K` for a list.
- `AS_T` (default `50,200`) – sequence length. Use `AS_SWEEP_T` for a list.
- `AS_TRIALS` (default `5`) – number of timing repetitions per case.

Notes:
- The benchmark enforces the interleaved (time-first) order to reflect optimal scaling.

FHMM order comparison (`fhmm_order_comparison.jl`):

- `AFH_SEED` (default `1`) – RNG seed.
- `AFH_C` (default `2`) – number of chains.
- `AFH_K` (default `4`) – number of states per chain.
- `AFH_T` (default `100`) – length of the sequence.
- `AFH_TRIALS` (default `10`) – timing samples per order.
- `AFH_MODE` (default `frontier`) – `frontier` or `timed`. Interleaved is always timed; the bad order is timed only if its proxy cost ≤ `AFH_COST_THRESH` (or when `AFH_MODE=timed`).
- `AFH_COST_THRESH` (default `1e8`) – threshold on the proxy Σ K^width (compared in log-space) to avoid intractable timings.
- `AFH_ORDERS` (optional) – comma‑separated list of orders to run. Accepted values: `interleaved`, `states_then_y`. Default runs both in that order. Example: `AFH_ORDERS=interleaved` or `AFH_ORDERS=states_then_y`.

Outputs CSV lines with columns
`order,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp`.
Two consistent orders are evaluated:
- `interleaved` (time‑first, tractable)
- `states_then_y` (all z’s, then all y’s; typically intractable for moderate T)

Output: CSV lines with columns
`seed,K,T,trials,min_time_sec,logp,max_frontier,mean_frontier,sum_frontier`.

When adding new scripts, document their environment variables near the top of
the file and list them here for quick reference.
