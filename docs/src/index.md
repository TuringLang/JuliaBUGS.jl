# Introduction

JuliaBUGS is a graph-based probabilistic programming language and a component of the Turing ecosystem.
The package aims to support modelling and inference for probabilistic programs written in the [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/) language.

This project is still in its early stage, with many key components needing to be completed.

Please refer to the [example](https://turinglang.org/JuliaBUGS.jl/stable/example/) for usage information and a complete example.

## What is BUGS?

The BUGS (Bayesian inference Using Gibbs Sampling) system is a probabilistic programming framework designed for specifying directed graphical models.
Unlike some other probabilistic programming languages (PPLs), such as Turing.jl or Pyro, the focus of BUGS is on specifying declarative relationships between nodes in a graph, which can be either logical or stochastic.
This means that explicit declarations of variables, inputs, outputs, etc., are not required, and the order of statements is not critical.

## The BUGS Approach and Benefits

Loops in BUGS are essentially a form of "plate notation," offering a concise way to express repetitive statements across many constant indices.
Variables in BUGS are either the names of nodes within the program or constant parts of the "data" that must be combined with a model for instantiation.

A BUGS model provides a comprehensive representation of the relationships and dependencies among a set of variables within a Bayesian framework.
Our goal is to support BUGS programs as much as possible while also incorporating Julia-specific syntax enhancements.

The key advantage of utilizing such a graph-based approach is the clarity it provides in understanding the dependencies and relationships within a complex system.
These graphical models allow users to explicitly state the conditional dependencies between variables.
This makes the model's structure and assumptions transparent, aiding both in the development and interpretation stages.
Furthermore, using such a graphical approach makes it easier to apply advanced algorithms for model inference, as it enables more efficient computation by identifying and exploiting the structure of the model.
