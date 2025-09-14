A convincing evaluation should make three claims land cleanly—**exactness**, **the right scaling law**, and **practical wins where discrete structure and heavy deterministics coexist**—and it should do so with models and data that readers already trust. Below is a concrete plan that you can implement in Julia/JuliaBUGS without exotic infrastructure. I describe the purpose of each experiment, how to set it up, what to measure, what you should expect to see if your story is true, and how the pieces fit into a coherent paper narrative.

---

### 1) Exactness and gradient correctness on small models

The first duty is to remove any doubt about correctness. On small mixed discrete–continuous Bayesian networks where brute force is still possible, show that your evaluator equals variable elimination (VE) numerically and that reverse‑mode AD yields the **exact Fisher‑identity gradient**.

**Setup.** Generate a family of tiny BNs with a mix of Bernoulli/Categorical latents $Q$ (say up to 10–12 total configurations) and a handful of Gaussian/Gamma continuous parameters $C$. Include deterministic nodes that combine parents linearly and nonlinearly (e.g., $\tanh$, small MLP). Evaluate the collapsed log‑joint $\log\sum_{q} p(y,q\mid c)$ in three ways: naïve enumeration, your runtime VE, and a VE implementation that materializes factors.

**Measures.** Absolute/relative error in value; cosine similarity between $\nabla_c$ from AD through your `logsumexp` and the gradient computed by explicitly summing $\sum_q p(q\mid y,c)\nabla_c\log p(y,q\mid c)$; wall‑clock per evaluation.

**What convinces.** Values match to machine precision between all three; gradients match to within numerical tolerance; runtimes agree up to constant factors. This anchors the later, larger experiments.

---

### 2) The scaling law: time/space track **weighted frontier width**

Your central claim is that time and memory scale with the discrete **frontier (cache) width**, not with the total number of discrete configurations. You should make that visible with controlled skeletons and orderings.

**Setup.** Build synthetic random skeletons $H$ with known vertex‑separation (pathwidth): (a) chains/HMMs (width 1), (b) ladders (width 2), and (c) small grids where width grows linearly with the shorter side. For each graph, assign non‑uniform discrete domain sizes (e.g., mix of 2‑, 4‑, 10‑state variables) and interleave cheap and heavy deterministic nodes. For each instance, run multiple topological orders: a good heuristic order (min‑fill/min‑degree on the moralized skeleton) and several random orders.

**Measures.** For each order $\pi$, compute your predicted widths $W(\pi)=\max_k \sum_{u\in K_k\cap Q}\log|\mathcal D_u|$ and $W^+(\pi)$ (adding the next‑site branch size). Measure peak cache size (number of distinct keys realized) and time per evaluation. Plot $\log$ time vs $W^+(\pi)$; plot $\log$ memory vs $W(\pi)$. Also report the number of times each heavy deterministic is executed.

**What convinces.** Nearly linear fits of $\log$ time on $W^+(\pi)$ and $\log$ memory on $W(\pi)$, with tight CIs; orders with smaller predicted widths win decisively; heavy deterministics execute exactly once per frontier key (not per branch). This empirically validates the complexity section of your paper.

---

### 3) Deterministic reuse matters: a real ODE model with discrete noise (runnable in JuliaBUGS)

Readers need to see a case where **one expensive, smooth computation is reused across many discrete branches**. Pharmacokinetics (Theophylline) with per‑measurement outlier indicators is perfect in JuliaBUGS.

**Model/data.** Use the Theoph dataset from `RDatasets`. Let $x(t)$ be the one‑compartment ODE trajectory with parameters $c=(k_a,k_e,V)$ and oral dose. For each observation $y_i$ at time $t_i$, introduce a binary indicator $z_i\in\{1,2\}$ that selects a tight or fat‑tailed observation noise. In BUGS:

* compute `x[1:T] <- pk1c_traj(t[1:T], ka, ke, V, dose)` **once** (pure deterministic);
* define `y[i] ~ dnorm(x[i], tau[z[i]])`;
* set a `dcat` prior for $z_i$ and weakly informative priors for $c$ and scales.

**Baselines.** (i) Your runtime VE collapsing all $z_i$; (ii) the **same** model but evaluated in the wrong order where the ODE is recomputed inside the likelihood loop (a legal but poor schedule); (iii) a non‑collapsed MCMC that samples $z_i$ (blocked Gibbs/Metropolis) to show mixing/efficiency differences.

**Measures.** Number of ODE solves per gradient evaluation (instrument a counter); wall‑clock per eval; acceptance rate and effective sample size per second (ESS/s) for NUTS on $c$; for the non‑collapsed baseline, ESS/s for $(c,z)$ and trace plots showing sticky $z$.

**What convinces.** Collapsing + good order yields **one** ODE solve per eval and high ESS/s; the bad order inflates ODE calls by a factor $\approx \mathbb{E}[\text{branch fan‑out}]$ with identical posterior; non‑collapsed sampling mixes worse or is inapplicable to HMC entirely. This makes the “place heavy deterministics to the left of the branch” message concrete.

---

### 4) A discrete global decision with a non‑trivial frontier: single changepoint

To illustrate a **non‑empty, but tiny** frontier, use a discrete changepoint on a standard time series (e.g., Nile flow). The discrete variable is the change index $s\in\{2,\dots,N-1\}$; the frontier at every cut is $\{s\}$.

**Setup.** BUGS model with `s ~ dcat(uniform)`, `mu[t] <- mu1 * (1 - step(t - s)) + mu2 * step(t - s)`, `y[t] ~ dnorm(mu[t], tau)`. Evaluate with your runtime VE so the objective becomes a single $\log\sum\exp$ over $N-2$ values.

**Measures.** Time vs $N$; posterior over $s$ (you can extract the softmax weights you already compute inside `logsumexp`); compare to a Gibbs sampler on $s$ to echo the historical mixing issue and show that collapsing makes HMC on $(\mu_1,\mu_2,\tau)$ straightforward.

**What convinces.** End‑to‑end smooth optimization/sampling on the continuous parameters while integrating out $s$ exactly; runtime grows with the support of $s$, not with time series length in a worse‑than‑linear way; the frontier‑key story is visible and interpretable.

---

### 5) Order selection matters: ablation across heuristics

You argued that users can control the space–time budget by choosing a visiting order. Make that operational.

**Setup.** On one synthetic and one real model (e.g., deep‑emission HMM with $K$ states and precomputed features, or the PK example if you introduce a discrete global switch), compare three orders: min‑fill/min‑degree on the moralized random skeleton, a random order, and an adversarial order that pushes heavy deterministics to the right.

**Measures.** Predicted $W(\pi), W^+(\pi)$; measured peak key count; wall‑clock per eval; number of heavy deterministic calls; end‑to‑end NUTS ESS/s.

**What convinces.** The heuristic order delivers the lowest widths and the best ESS/s, matching the predictions; adversarial orders degrade exactly in proportion to the added branch fan‑out or widened frontier.

---

### 6) Circuit/VE compilation vs runtime VE (optional but strong)

If you can, include a small comparison against a compiled factor/circuit approach on models without heavy deterministics (e.g., HMM with categorical emissions). The point is not to beat compilers on their home turf, but to show that when deterministics are light, you are competitive; and when deterministics are heavy and pure, runtime VE keeps reuse without building a circuit that would have to inline the heavy code.

**Measures.** Preprocessing/compile time; per‑eval time; memory.
**What convinces.** Competitive numbers with zero compile time in the “light deterministic” regime; decisive wins once you place a heavy pure function on the left of a branch.

---

## Metrics and reporting that reviewers trust

Favor *mechanistic* metrics that map to your theory: $\sum_k |\Xi_k|$ (number of contexts per entry), $\max_k |\Xi_k|$ (peak cache width), measured `logsumexp` fan‑out $B_k$, and counts of heavy deterministic calls. Always normalize end‑to‑end sampler performance by ESS/s, not wall‑clock alone. For gradient checks, use value‑and‑gradient pairs from small exact sums; for ODE models, note explicitly which adjoint mode you used so results are reproducible.

## What to avoid (and how to preempt reviewer concerns)

Avoid models where hard thresholds depend on unknown **continuous** parameters (e.g., `step(theta - x[i])`), which break differentiability and are a poor fit for HMC; if you must include such logic, introduce an explicit discrete gate and collapse it. Make clear that your deterministics are **pure** and side‑effect free; mutation across branches would invalidate suffix caching. Finally, when demonstrating order effects, ensure that orders are equally valid topologically so you’re not changing semantics—only the schedule.

## Artifact and reproducibility

Ship a small repository with: (i) `exactness/` tiny synthetic BNs and the enumeration check; (ii) `scaling/` scripts that sweep graph families and orders and emit the width vs time/memory plots; (iii) `pk_theoph/` and `changepoint_nile/` folders with JuliaBUGS models, data loading via `RDatasets`, and NUTS harnesses; and (iv) a `metrics.jl` utility that logs the number of heavy deterministic calls and realized cache keys per evaluation. Pin package versions and random seeds. Each figure in the paper should correspond to a single script with a command‑line flag for the panel.

---

### How these experiments answer the paper’s claims

Section 1 nails **correctness** (value and gradients). Section 2 demonstrates the **scaling law** with frontier width and validates the role of ordering. Sections 3–4 provide **compelling, runnable models** where finite discretes and heavy deterministics meet and your method changes the wall‑clock reality without compromising exactness. Section 5 shows that practitioners can control costs via ordering, as you claim. Section 6, if included, situates runtime VE against compilation‑based alternatives.

If you implement just three figures, prioritize: the frontier‑width scaling plot; the ODE + outlier PK result with a reuse ablation; and the single changepoint with the posterior over $s$ and an HMC trace—together they make the story hard to argue with.
