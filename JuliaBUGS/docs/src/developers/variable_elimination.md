# Variable Elimination for Auto-Marginalization

This note describes how `UseAutoMarginalization` sums finite discrete latents out of the
log density by variable elimination. The code is in `src/model/variable_elimination.jl`.

## Problem

The frontier recursion (`_marginalize_recursive`) walks the nodes in an order, branches on
each latent, and memoizes partial sums keyed by the latents that still matter downstream. It
recurses once per node, so a hidden Markov model with a few thousand time steps overflows the
stack, and its cost depends on how well the chosen node order separates the latents.

## Idea

With the continuous parameters fixed, the term each scored stochastic node adds to the log
joint depends on the latents only through the latents it reads, directly or through
deterministic nodes. Call that set its scope. Then

    log p(θ, y) = base + log Σ_z exp(Σ_f φ_f(z[scope(f)]))

where `base` collects the terms with an empty scope and each `φ_f` is a small table over its
scope. The sum over all configurations is computed by summing the latents out one at a time:
take the tables that depend on a latent, add them, and `logsumexp` over that latent. The
result is a table over the remaining latents in their scopes.

## Plan (built once, with the marginalization cache)

1. **Scopes.** In topological order: a latent's value has itself as scope; a deterministic
   node's has the union of its parents'; a continuous parameter's is empty, unless its
   bijector carries parameters (`a ~ dunif(lo[x], hi[x])`). In that case its value
   `inverse(bijector(dist))(θ)` depends on its parents, and it passes their scope on.
2. **Factors.** One per scored node (latent, continuous parameter, observation) whose scope
   is not empty, with the deterministic nodes and parameters to recompute for each
   configuration. Nodes with an empty scope are scored once.
3. **Domains.** Only Bernoulli and categorical latents, whose support is fixed by their type
   and shape, are planned.
4. **Order.** Latents are eliminated from the last to the first in topological order. On a
   chain this is the backward pass of the forward-backward algorithm, and on a tree it is
   optimal.

The plan is `nothing`, and the frontier recursion is used, when a latent has another
distribution (its support could depend on its parents), when a table would have more than
2^20 entries, or when a continuous parameter is missing from the parameter layout.

## Evaluation

1. Set the continuous parameters and the values that do not depend on latents, and score the
   nodes with an empty scope.
2. Fill each factor's table: for every configuration of its scope, set the latents,
   recompute the dependent nodes, and evaluate the node's log density. `NaN` counts as
   `-Inf`, as in the frontier recursion.
3. Run the elimination twice: over all factors (the log joint) and over the prior factors
   only (the log prior). The log likelihood is the log joint minus the log prior, so the
   split and tempering are the same as with the frontier recursion.

Control flow depends only on the plan, never on parameter values, so it works with
ForwardDiff, Mooncake, and ReverseDiff tapes.

## Scope

Recovering the latents for generated quantities (`_sample_discrete_latents!!`) still uses
the frontier recursion. Factor tables are filled with one dynamic call per entry, which keeps
the code short; grouping factors by statement, as the graph evaluation plan does for nodes,
would make filling them faster.
