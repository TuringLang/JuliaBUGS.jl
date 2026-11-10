# Graph Evaluation Plan

This note describes how `UseGraph` evaluates the log density. The code is in
`src/model/evaluation_plan.jl`.

## Problem

A BUGS loop is unrolled into one graph node per element. Graph mode used to visit those
nodes one at a time, reading the node function, loop variables, and name from `Any`-typed
vectors. Every node therefore paid for a dynamic dispatch, a `Dict` lookup of its parameter
length, and an update of the evaluation environment the compiler could not see through. On
Rats (367 nodes) that overhead was most of the cost.

## Idea

Nodes unrolled from the same statement share a node function and have the same types. Run
them together:

1. Group the nodes that log-density evaluation visits by node function, node kind
   (deterministic, parameter, observation), loop-variable type, and `VarName` type.
2. Order the nodes topologically, keeping each group's ready nodes together, so every node
   still runs after its parents.
3. Store each group as a concretely typed `NodeRun` and evaluate it with one loop.

Dispatch now happens once per run instead of once per node, and the node function inlines
into the loop. Rats has 9 runs.

## Ordering

The order comes from Kahn's algorithm with the ready nodes bucketed by group. A bucket is
emptied, including members that become ready meanwhile, before another starts. A complete
bucket goes first, then one whose nodes unblock others; observations, which unblock nothing,
wait until their group is complete.

A statement whose nodes depend on another statement's nodes is split into several runs. A
hidden Markov model alternates between statements at every step, so each run holds one node:
it is still correct, just not faster.

Correctness relies on the graph's edges listing every value a node function reads, which the
compiler guarantees.

## What does not change

- Which nodes are visited, and what each computes.
- The parameter layout: offsets into the flat vector follow `sorted_nodes`.
- Writes use the same `BangBang.setindex!!`, so a field widens (for example an integer array
  receiving a float) exactly as before. A run that widens a field continues in a call
  specialized on the new type.

Only the order in which log-density terms are summed differs, which can change the last bits.

## Keeping the plan current

The plan is stored in `BUGSModel.evaluation_plan`. It is built with the model and rebuilt by
the keyword constructor `BUGSModel(model; ...)` whenever the graph data, parameter lengths,
mutable symbols, or environment fields change, which covers `condition`, `fix`, and the
reordering done by generated mode.

The plan records the objects it was built from. Before using it, evaluation checks that the
model still holds those same objects; if not (a field replaced with `BangBang.setproperty!!`),
it uses the node-by-node evaluator, kept as `_evaluate_with_values_in_sorted_order!!`. Tests
use that evaluator as the reference.

## World age

Node functions are created by `eval`, so they can be newer than the caller's world. The
plan calls the plain source functions, which lets them inline. When the caller's world is
older than the plan, evaluation enters the latest world once with `invokelatest`, instead of
paying an OpaqueClosure call per node. Mooncake and Enzyme already differentiate a model
built from source functions, whose plan never needs `invokelatest`.

## Scope

Only `evaluate_with_values!!` and `LogDensityProblems.logdensity` use the plan.
`evaluate_with_env!!` is unchanged, and `evaluate_with_rng!!` must keep visiting nodes in
`sorted_nodes` order because the order of random draws is observable.
