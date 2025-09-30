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

## 2025-09-24 — HMT order comparison (frontier-only; DFS timed)

- Script: `JuliaBUGS/experiments/scripts/hmt_order_comparison.jl`
- Config A (frontier-only): `AHMT_B=2`, `AHMT_DEPTH=8`, `AHMT_K=4`, `AHMT_MODE=frontier`.
- Config B (DFS timed only): same but `AHMT_MODE=dfs`.
- Output (order,B,K,depth,N,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp):
  - Frontier-only:
    - `random_dfs,2,4,8,255,8,3.765,1920,1.321e+01,NA,NA`
    - `bfs,2,4,8,255,65,32.624,16638,9.134e+01,NA,NA`
    - `dfs,2,4,8,255,8,3.765,1920,1.321e+01,NA,NA`
  - DFS timed:
    - `dfs,2,4,8,255,8,3.765,1920,1.321e+01,1.810321e+00,-340.498985428238`
- Notes: BFS exhibits a large frontier (≈65 at depth 8) and a much larger cost proxy than DFS/randomized-DFS (≈8), consistent with tree pathwidth intuition. We avoid timing BFS due to proxy-based guard.

## 2025-09-24 — FHMM order sweep (frontier-only for bad order)

- Script: `JuliaBUGS/experiments/scripts/fhmm_order_comparison.jl`
- Config: `AFH_C=2`, `AFH_K=4`, `AFH_T∈{20,40,80,100}`, `AFH_TRIALS=10`, `AFH_MODE=frontier`.
- Output (order,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp):
  - T=20
    - `interleaved,2,1.970,197,7.361e+00,4.105792e-03,-32.517423501802`
    - `states_then_y,40,20.200,2020,5.646e+01,NA,NA`
  - T=40
    - `interleaved,2,1.985,397,8.062e+00,1.012017e-02,-58.665977213007`
    - `states_then_y,80,40.200,8040,1.119e+02,NA,NA`
  - T=80
    - `interleaved,2,1.992,797,8.760e+00,2.624392e-02,-121.075969900975`
    - `states_then_y,160,80.200,32080,2.228e+02,NA,NA`
  - T=100
    - `interleaved,2,1.994,997,8.984e+00,3.694283e-02,-159.084764499352`
    - `states_then_y,200,100.200,50100,2.783e+02,NA,NA`
- Notes: Bad order’s proxy grows rapidly with T while interleaved remains near constant frontier≈C; timings reported only for interleaved per guard.

## 2025-09-24 — FHMM C-sweep (interleaved only; K=4, T=100)

- Script: `JuliaBUGS/experiments/scripts/fhmm_order_comparison.jl`
- Config: `AFH_K=4`, `AFH_T=100`, `AFH_TRIALS=10`, `AFH_MODE=timed`, `AFH_ORDERS=interleaved`, `C∈{2,3,4}`.
- Output (order,max_frontier,mean_frontier,sum_frontier,log_cost_proxy,min_time_sec,logp):
  - `C=2: interleaved,2,1.994,997,8.984e+00,3.621279e-02,-159.084764499352`
  - `C=3: interleaved,3,2.991,2094,1.071e+01,1.619965e-01,-174.241807200349`
  - `C=4: interleaved,4,3.989,3590,1.234e+01,8.969850e-01,-185.112139413195`
- Notes: Max frontier≈C and runtime increases with C, consistent with the frontier lens.

## 2025-09-24 — HMT depth sweep (B=2, K=4): frontier-only vs DFS timed

- Script: `JuliaBUGS/experiments/scripts/hmt_order_comparison.jl`
- Configs per depth d∈{4,6,8,10}:
  - Frontier-only: `AHMT_MODE=frontier`
  - DFS-only timed: `AHMT_MODE=dfs`
- Highlights (order,B,K,depth,N,max_frontier,log_cost_proxy,min_time_sec):
  - `d=4`: BFS `max_frontier=5`, `log_cost_proxy≈8.154`; DFS `min_time_sec=2.048e-03`
  - `d=6`: BFS `max_frontier=17`, `log_cost_proxy≈24.80`; DFS `min_time_sec=5.489e-02`
  - `d=8`: BFS `max_frontier=65`, `log_cost_proxy≈91.34`; DFS `min_time_sec=1.806e+00`
  - `d=10`: BFS `max_frontier=257`, `log_cost_proxy≈357.5`; DFS `min_time_sec=7.087e+01`
- Notes: BFS frontier grows rapidly with depth; DFS time grows smoothly; we avoid timing BFS across depths.

## 2025-09-24 — GMM correctness sweep (fresh run)

- Script: `JuliaBUGS/experiments/scripts/gmm_correctness_sweep.jl`
- Config: `AG_SWEEP_SEEDS=1`, `AG_SWEEP_K=2,4`, `AG_SWEEP_N=100,1000`.
- Outputs (seed,K,N,logp_autmarg,logp_closed_form,diff):
  - `1,2,100,-204.416329424201,-204.416329424201,-5.684e-14`
  - `1,2,1000,-1970.291568636987,-1970.291568637027,4.047e-11`
  - `1,4,100,-203.586552750729,-203.586552750729,-2.558e-13`
  - `1,4,1000,-1948.173739898702,-1948.173739898751,4.843e-11`

## 2025-09-24 — HMM correctness sweep (fresh run)

- Script: `JuliaBUGS/experiments/scripts/hmm_correctness_sweep.jl`
- Config: `AM_SWEEP_SEEDS=1`, `AM_SWEEP_K=2,4`, `AM_SWEEP_T=50,200`.
- Outputs (seed,K,T,logp_autmarg,logp_forward,diff):
  - `1,2,50,-79.870504305836,-79.870504305836,5.684e-14`
  - `1,2,200,-278.627031832427,-278.627031832427,-4.547e-13`
  - `1,4,50,-71.473518232377,-71.473518232377,1.421e-14`
  - `1,4,200,-275.848467761660,-275.848467761659,-2.274e-13`

## 2025-09-24 — Gradient checks (fresh runs)

- Scripts: `hmm_gradient_check.jl`, `gmm_gradient_check.jl`, `hdphmm_gradient_check.jl`.
- HMM (seed=1, K=2, T=50): `logp=-80.444277269128`, `max_abs_diff=2.422e-09`, `max_rel_diff=8.995e-10`.
- GMM (seed=1, K=2, N=200): `logp=-468.030155527501`, `max_abs_diff=6.644e-08`, `max_rel_diff=4.846e-08`.
- HDP-HMM non-sticky (seed=1, K=5, T=200): `logp=-403.142155296914`, `max_abs_diff=2.478e-07`, `max_rel_diff=1.388e-03`.
- HDP-HMM sticky κ=5.0 (seed=1, K=5, T=120): `logp=-236.450382897373`, `max_abs_diff=9.347e-08`, `max_rel_diff=1.402e-03`.
## 2025-09-24 — HMM scaling sweep (expanded K,T; interleaved; min_time)

- Script: `JuliaBUGS/experiments/scripts/hmm_scaling_bench.jl`
- Config: `AS_SWEEP_SEEDS=1`, `AS_SWEEP_K=8,16,32,64`, `AS_SWEEP_T=50,100,200,400,800`, `AS_TRIALS=15`.
- Output (seed,K,T,trials,min_time_sec,logp,max_frontier,mean_frontier,sum_frontier):
  - `1,8,50,15,4.031500e-03,-68.367716912908,1,0.990,99`
  - `1,8,100,15,1.053150e-02,-134.566394931630,1,0.995,199`
  - `1,8,200,15,3.109333e-02,-268.884504181967,1,0.998,399`
  - `1,8,400,15,1.032710e-01,-507.899254715377,1,0.999,799`
  - `1,8,800,15,3.868640e-01,-1014.031647189991,1,0.999,1599`
  - `1,16,50,15,1.096975e-02,-68.640930263672,1,0.990,99`
  - `1,16,100,15,2.583529e-02,-132.615884733434,1,0.995,199`
  - `1,16,200,15,6.208867e-02,-264.898444018715,1,0.998,399`
  - `1,16,400,15,1.653278e-01,-496.082331882703,1,0.999,799`
  - `1,16,800,15,5.194480e-01,-994.008267544666,1,0.999,1599`
  - `1,32,50,15,3.842762e-02,-67.917939032965,1,0.990,99`
  - `1,32,100,15,8.173317e-02,-131.957904902438,1,0.995,199`
  - `1,32,200,15,1.783575e-01,-262.204812107237,1,0.998,399`
  - `1,32,400,15,4.249979e-01,-490.584185596219,1,0.999,799`
  - `1,32,800,15,1.098389e+00,-983.156598392055,1,0.999,1599`
  - `1,64,50,15,1.534776e-01,-67.624721238144,1,0.990,99`
  - `1,64,100,15,3.294130e-01,-130.774108588117,1,0.995,199`
  - `1,64,200,15,7.271693e-01,-260.703706812903,1,0.998,399`
  - `1,64,400,15,1.479587e+00,-487.252773745216,1,0.999,799`
  - `1,64,800,15,3.091532e+00,-976.386085472905,1,0.999,1599`
- Notes:
  - Normalized `time_over_TK2` (min time divided by `T*K^2`) plateaus for `K≥16` with mean≈1.09e-06 (min 7.49e-07, max 2.54e-06 over 15 cases). For `K=8` it is higher and more variable (mean≈3.39e-06), indicating overhead dominance at small K.
  - Frontier metrics remain near the theoretical minimum (max≈1) for the enforced interleaved order.
