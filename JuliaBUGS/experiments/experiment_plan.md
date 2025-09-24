# Streamlined Auto-Marginalization Experiment Plan

## Core Validation: Essential Evidence
**Goal**: Prove correctness and demonstrate core algorithmic advantages

1) **Correctness Validation**
- HMM: K ∈ {2, 4}, T ∈ {50, 200} vs forward-backward reference
- GMM: K ∈ {2, 4}, N ∈ {100, 1000} vs analytical collapsed likelihood
- Gradient verification via finite differences
- *Status: Partially implemented, needs expansion*

2) **Scaling Demonstration**
- HMM temporal ordering: measure O(T·K²) scaling
- Peak frontier width profiling during evaluation
- *Status: Basic benchmarks exist, needs theoretical overlay*

## Critical Impact Demo: Order Matters
**Goal**: Show dramatic practical importance of variable ordering

3) **Factorial HMM Order Comparison**
- C ∈ {2, 3, 4} chains, T = 100
- Compare policies: interleaved (time‑first) vs min‑fill vs min‑degree (weighted by log K), with randomized tie‑breaks and a few restarts; report best of R restarts per heuristic.
- Replace “worst‑case” (grouped/random) with practical heuristics; avoid pathological explosions.
- Metrics:
  - Frontier stats: max/mean/sum width over evaluation order
  - Predicted DP cost proxy: Σ_t K^{w_t} (or Σ_t exp(Σ_i log K_i) for heterogeneous K)
  - Timing: always time interleaved; time heuristic orders only if predicted cost < threshold (frontier‑only mode otherwise). Verify equal logp on small T.
- Order construction: build discrete primal graph; generate elimination order via heuristic; lift to evaluation order by placing emissions as soon as all discrete parents are placed; topo‑repair; recompute minimal keys.
- *Status: Heuristic plan defined; utils in place; implement min‑fill/min‑degree + frontier‑only reporting*

## Theoretical Generalization: Beyond Chains
**Goal**: Demonstrate algorithmic generality

4) **Tree Structure Validation**
- Binary HMT: DFS vs BFS vs random orders
- Show near-optimal frontier management
- *Status: Not implemented*

## Nonparametric Extension: Exact Finite Truncation
**Goal**: Show method works for nonparametric models with finite support

5) **HDP-HMM with Truncation**
- Stick-breaking with K_max ∈ {5, 10, 20}
- Marginalize assignments exactly under truncation
- Compare against forward-backward with same truncation
- Demonstrate exact gradients w.r.t. hyperparameters
- *Status: Not implemented*

## Implementation Priorities

**Core Validation**
1. Extend existing HMM/GMM correctness tests with more configurations
2. Add theoretical complexity curve overlays to existing benchmarks
3. Implement gradient verification via finite differences

**Order Impact**
4. Implement FHMM with heuristic orders (interleaved, min‑fill, min‑degree)
5. Add frontier‑only mode with predicted cost proxy and timing threshold; time interleaved by default
6. Add randomized restarts for heuristics with weighted scores (log K) and select the best

**Generalization**
7. Add basic tree model (HMT) with heuristic orders (DFS‑like, min‑fill/min‑degree on tree moralization)
8. Implement HDP-HMM with truncation and exact marginalization

**Infrastructure**
- Extend existing experiment harness for structured logging
- Add frontier profiling and complexity proxy generation (Σ K^{w_t})
- Add skip/timeout guards based on predicted cost; record “skipped” in logs
