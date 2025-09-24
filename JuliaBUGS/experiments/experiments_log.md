# Auto-Marginalization Experiments Log

All commands are assumed to be run from the repo root with the experiments
project: `julia --project=JuliaBUGS/experiments …`.

## 2024-09-24 — HMM marginal logp check

- Script: `JuliaBUGS/experiments/scripts/hmm_marginal_logp.jl`
- Default config (`AM_SEED=1`, `AM_T=50`, `K=2`).
- Output:
  - Auto-marg logp: `-44.994096`
  - Forward reference: `-44.994096`
  - Delta: `-4.97e-14`
- Notes: First deterministic check; script reads env vars `AM_SEED`, `AM_T`.

## 2024-09-24 — HMM correctness sweep

- Script: `JuliaBUGS/experiments/scripts/hmm_correctness_sweep.jl`
- Config: defaults (`AM_SWEEP_SEEDS=1`, `AM_SWEEP_K=2,4`, `AM_SWEEP_T=50,200`).
- Outputs (seed,K,T,logp_autmarg,logp_forward,diff):
  - `1,2,50,-79.870504305836,-79.870504305836,5.684e-14`
  - `1,2,200,-278.627031832427,-278.627031832427,-4.547e-13`
  - `1,4,50,-71.473518232377,-71.473518232377,1.421e-14`
  - `1,4,200,-275.848467761660,-275.848467761659,-2.274e-13`
- Notes: Confirms auto-marg matches forward algorithm across plan’s grid.

## 2024-09-24 — GMM correctness sweep

- Script: `JuliaBUGS/experiments/scripts/gmm_correctness_sweep.jl`
- Config: defaults (`AG_SWEEP_SEEDS=1`, `AG_SWEEP_K=2,4`, `AG_SWEEP_N=100,1000`).
- Outputs (seed,K,N,logp_autmarg,logp_closed_form,diff):
  - `1,2,100,-204.416329424201,-204.416329424201,-5.684e-14`
  - `1,2,1000,-1970.291568636987,-1970.291568637027,4.047e-11`
  - `1,4,100,-203.586552750729,-203.586552750729,-2.558e-13`
  - `1,4,1000,-1948.173739898702,-1948.173739898751,4.843e-11`
- Notes: Analytic marginal and auto-marg agree up to numerical precision.

## 2024-09-24 — HMM gradient verification (AutoMarg target)

- Script: `JuliaBUGS/experiments/scripts/hmm_gradient_check.jl`
- Config: defaults (`AGC_SEED=1`, `AGC_K=2`, `AGC_T=50`).
- Output (excerpt):
  - `logp = -126.799281599876`
  - `θ[1]: autodiff=1.438140e+02 fd=1.438140e+02 diff=-2.41e-09`
  - `θ[2]: autodiff=-8.204939e+01 fd=-8.204939e+01 diff=3.40e-09`
  - `θ[3]: autodiff=8.965588e+00 fd=8.965588e+00 diff=6.22e-10`
  - `θ[4]: autodiff=4.711574e+00 fd=4.711574e+00 diff=1.37e-09`
- Notes: Gradients from ForwardDiff match central finite differences to ~1e-9.

## 2024-09-24 — HMM gradient verification (sweep-enabled, default run)

- Script: `JuliaBUGS/experiments/scripts/hmm_gradient_check.jl`
- Config: defaults (`AGC_SEED=1`, `AGC_K=2`, `AGC_T=50`, `AGC_EPS=1e-5`, `AGC_VERBOSE=0`).
- Summary:
  - `logp = -80.444277269128`
  - `max_abs_diff = 2.422e-09`, `max_rel_diff = 8.995e-10`
- Notes: Script now supports sweeps via `AGC_SWEEP_SEEDS`, `AGC_SWEEP_K`, `AGC_SWEEP_T` and per‑θ verbose output via `AGC_VERBOSE=1`.

## 2024-09-24 — GMM gradient verification

- Script: `JuliaBUGS/experiments/scripts/gmm_gradient_check.jl`
- Config: defaults (`AGG_SEED=1`, `AGG_K=2`, `AGG_N=200`, `AGG_EPS=1e-5`, `AGG_VERBOSE=0`).
- Summary:
  - `logp = -468.030155527501`
  - `max_abs_diff = 6.644e-08`, `max_rel_diff = 4.846e-08`
- Notes: Validates gradients w.r.t. continuous parameters (`mu`, `log_sigma`) under auto‑marginalization with fixed uniform weights; sweep supported via `AGG_SWEEP_*`.

## 2024-09-24 — HMM scaling benchmark (auto-marginalization)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: defaults (`AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=2,4`, `AS_SWEEP_T=50,200`, `AS_TRIALS=5`).
- Output (seed,K,T,trials,mean_time_sec,logp,max_frontier,mean_frontier,sum_frontier):
  - `1,2,50,5,1.747571e-02,-79.870504305836,1,0.990,99`
  - `1,2,200,5,3.401337e-02,-278.627031832427,1,0.998,399`
  - `1,4,50,5,1.657132e-02,-71.473518232377,1,0.990,99`
  - `1,4,200,5,3.799386e-02,-275.848467761660,1,0.998,399`
- Notes: Mean times grow roughly linearly in T. Frontier metrics reflect interleaved‑like minimal width (max_frontier≈1) under the model’s cached order.

## 2024-09-24 — HMM scaling sweep (interleaved order)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=2,4,8`, `AS_SWEEP_T=50,100,200,400,800`, `AS_TRIALS=5`.
- Output (seed,K,T,trials,mean_time_sec,logp,max_frontier,mean_frontier,sum_frontier):
  - `1,2,50,5,1.725919e-02,-79.870504305836,1,0.990,99`
  - `1,2,100,5,2.026912e-02,-145.761382159410,1,0.995,199`
  - `1,2,200,5,2.251455e-02,-278.627031832427,1,0.998,399`
  - `1,2,400,5,9.836627e-02,-528.062883321577,1,0.999,799`
  - `1,2,800,5,3.282191e-01,-1049.936193752744,1,0.999,1599`
  - `1,4,50,5,1.502275e-02,-71.473518232377,1,0.990,99`
  - `1,4,100,5,7.704333e-03,-137.896475262787,1,0.995,199`
  - `1,4,200,5,2.397348e-02,-275.848467761660,1,0.998,399`
  - `1,4,400,5,8.882374e-02,-525.491535975989,1,0.999,799`
  - `1,4,800,5,3.479876e-01,-1045.351313078216,1,0.999,1599`
  - `1,8,50,5,5.099008e-03,-68.367716912908,1,0.990,99`
  - `1,8,100,5,1.158021e-02,-134.566394931630,1,0.995,199`
  - `1,8,200,5,3.383068e-02,-268.884504181967,1,0.998,399`
  - `1,8,400,5,1.070151e-01,-507.899254715377,1,0.999,799`
  - `1,8,800,5,4.041233e-01,-1014.031647189991,1,0.999,1599`

## 2024-09-24 — HMM scaling sweep (min_time_sec, interleaved order)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=2,4,8`, `AS_SWEEP_T=50,100,200,400,800`, `AS_TRIALS=5`.
- Output (seed,K,T,trials,min_time_sec,logp,max_frontier,mean_frontier,sum_frontier):
  - `1,2,50,5,1.822208e-03,-79.870504305836,1,0.990,99`
  - `1,2,100,5,5.764750e-03,-145.761382159410,1,0.995,199`
  - `1,2,200,5,2.135263e-02,-278.627031832427,1,0.998,399`
  - `1,2,400,5,8.513233e-02,-528.062883321577,1,0.999,799`
  - `1,2,800,5,3.454963e-01,-1049.936193752744,1,0.999,1599`
  - `1,4,50,5,2.201750e-03,-71.473518232377,1,0.990,99`
  - `1,4,100,5,6.811584e-03,-137.896475262787,1,0.995,199`
  - `1,4,200,5,2.401713e-02,-275.848467761660,1,0.998,399`
  - `1,4,400,5,9.021662e-02,-525.491535975989,1,0.999,799`
  - `1,4,800,5,3.536854e-01,-1045.351313078216,1,0.999,1599`
  - `1,8,50,5,4.020833e-03,-68.367716912908,1,0.990,99`
  - `1,8,100,5,1.082317e-02,-134.566394931630,1,0.995,199`
  - `1,8,200,5,3.241446e-02,-268.884504181967,1,0.998,399`
  - `1,8,400,5,1.081037e-01,-507.899254715377,1,0.999,799`
  - `1,8,800,5,3.867681e-01,-1014.031647189991,1,0.999,1599`

## 2024-09-24 — HMM scaling (K^2 normalization, interleaved order)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=8,16,32,64`, `AS_SWEEP_T=400`, `AS_TRIALS=20`.
- Derived metric: `time_over_TK2 = mean_time_sec / (T*K^2)`.
- Results:
  - `K=8,  T=400, trials=20, mean_time_sec=1.221838e-01, time_over_TK2=4.772805e-06`
  - `K=16, T=400, trials=20, mean_time_sec=1.921807e-01, time_over_TK2=1.876765e-06`
  - `K=32, T=400, trials=20, mean_time_sec=4.844382e-01, time_over_TK2=1.182710e-06`
  - `K=64, T=400, trials=20, mean_time_sec=1.484085e+00, time_over_TK2=9.058136e-07`

## 2024-09-24 — HMM scaling (larger K, min_time_sec)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=8,16,32,64,128`, `AS_SWEEP_T=400`, `AS_TRIALS=10`.
- Results (normalized with `time_over_TK2 = min_time_sec/(T*K^2)`):
  - `K=8,  T=400, min_time_sec=1.040547e-01, time_over_TK2=4.064637e-06`
  - `K=16, T=400, min_time_sec=1.634169e-01, time_over_TK2=1.595868e-06`
  - `K=32, T=400, min_time_sec=4.772193e-01, time_over_TK2=1.165086e-06`
  - `K=64, T=400, min_time_sec=1.436576e+00, time_over_TK2=8.768164e-07`
  - `K=128, T=400, min_time_sec=5.412097e+00, time_over_TK2=8.258205e-07`

## 2024-09-24 — HMM scaling (very large K, min_time_sec)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=256,512`, `AS_SWEEP_T=400`, `AS_TRIALS=5` (K=512 used 3 trials).
- Results (normalized with `time_over_TK2 = min_time_sec/(T*K^2)`):
  - `K=256, T=400, min_time_sec=2.061049e+01, time_over_TK2=7.862278e-07`
  - `K=512, T=400, min_time_sec=8.741909e+01, time_over_TK2=8.336934e-07`

## 2025-09-24 — FHMM order comparison (tiny T; consistent orders)

- Script: `JuliaBUGS/experiments/scripts/fhmm_order_comparison.jl`
- Config: `AFH_MODE=timed`, `AFH_C=2`, `AFH_K=2`, `AFH_TRIALS=20`.
- Orders: `interleaved` (good), `states_then_y` (all z’s then all y; bad).

Results (order,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp):

- T=5
  - `states_then_y,10,5.200,130,8.397e+00,9.741708e-03,-11.605424781297`
  - `interleaved,2,1.880,47,4.554e+00,2.232500e-04,-11.605424781297`

- T=8
  - `states_then_y,16,8.200,328,1.256e+01,1.142920e+00,-21.198978101373`
  - `interleaved,2,1.925,77,5.043e+00,4.742500e-04,-21.198978101373`

- T=10
  - `states_then_y,20,10.200,510,1.533e+01,2.566664e+01,-23.230717049023`
  - `interleaved,2,1.940,97,5.273e+00,5.868750e-04,-23.230717049023`

Notes:
- Both orders agree on logp for the same data; differences are purely computational.
- The frontier lens explains tractability: interleaved keeps max_frontier≈C, while
  states_then_y grows roughly with T, making Σ K^{width} explode quickly.
- New env var `AFH_ORDERS` allows selecting orders to run, e.g. `AFH_ORDERS=interleaved`
  or `AFH_ORDERS=states_then_y`.


## 2025-09-24 — HDP-HMM correctness (finite truncation, sticky optional)

- Script: `JuliaBUGS/experiments/scripts/hdphmm_correctness_fixed.jl`
- Config: `AHDPC_SEEDS=1`, `AHDPC_K=5,10`, `AHDPC_T=100,200`, `AHDPC_ALPHA=5.0`, `AHDPC_GAMMA=1.0`, `AHDPC_KAPPA=0.0`.
- Output (seed,K,T,alpha,gamma,logp_autmarg,logp_forward,diff):
  - `1,5,100,5.000,1.000,-132.648742618434,-132.648742618434,0.000e+00`
  - `1,5,200,5.000,1.000,-263.448999241194,-263.448999241194,1.137e-13`
  - `1,10,100,5.000,1.000,-94.917105497644,-94.917105497644,-7.105e-14`
  - `1,10,200,5.000,1.000,-175.671119347952,-175.671119347951,-9.095e-13`
- Notes: Auto-marginalized log p(y|β,π,μ,σ) matches forward reference up to numerical precision. Sticky variant supported via `AHDPC_KAPPA` (default 0.0).

## 2025-09-24 — HDP-HMM gradient verification

- Script: `JuliaBUGS/experiments/scripts/hdphmm_gradient_check.jl`
- Config: `AHDPG_SEED=1`, `AHDPG_K=5`, `AHDPG_T=200`, `AHDPG_ALPHA=5.0`, `AHDPG_GAMMA=1.0`, `AHDPG_EPS=5e-6`.
- Summary:
  - `logp = -403.142155296914`
  - `max_abs_diff = 4.926e-08`, `max_rel_diff = 1.388e-03`
- Notes: Gradients validated for μ, log σ, stick v, and π rows under Dirichlet(α·β). Sticky κ is used in the correctness script; gradient script uses non‑sticky rows to satisfy BUGS single‑assignment constraints.

## 2025-09-24 — HDP-HMM gradient verification (sticky)

- Script: `JuliaBUGS/experiments/scripts/hdphmm_gradient_check.jl`
- Config: `AHDPG_SEED=1`, `AHDPG_K=5`, `AHDPG_T=120`, `AHDPG_ALPHA=5.0`, `AHDPG_GAMMA=1.0`, `AHDPG_KAPPA=5.0`, `AHDPG_EPS=5e-6`.
- Summary:
  - `logp = -236.450382897373`
  - `max_abs_diff = 9.347e-08`, `max_rel_diff = 1.402e-03`
- Notes: Implemented sticky prior in-gradient via deterministic `diagshift` primitive to keep single-assignment and AD friendliness; validates end‑to‑end gradients with z marginalized.
