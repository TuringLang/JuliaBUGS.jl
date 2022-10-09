# SymbolicPPL.jl

This package contains some infrastructure to work with graphical probabilistic models in symbolic form, consisting of a model DSL (which one could call "frontend"), an attempt of its formalization (ongoing work), and AbstractPPL-compatible evaluation facilities (i.e., sampling and density evaluation, conditioning, etc.).

## Caution!

This implementation should be able to parse existing BUGS models and run them.  It is, however, still a bit sketchy, potentially very inefficient, and certainly not yet ready for serious work.  

We are (as of autumn 2022) planning to continually keep working on this project, until we have a mature BUGS-compatible graphical PPL system integrated in the Turing ecosystem.

## Syntax & model representation

We provide some convenience functions to work with graphical models syntactically in Julia, inspired very much by [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/).
BUGS (Bayesian inference Using Gibbs Sampling), as the name says, is a probabilistic programming system originally designed for Gibbs sampling.
For this purpose, BUGS models define, implicitly, only a directed graph of variables, not an ordered sequence of statements like other PPLs.
They do have the advantage of being relatively restricted (while still able to express a very large class of practically used models), and hence allowing lots of static analysis.  
Specifically, stochastic control flow is disallowed (except for the “mixture model” case of indexing by a stochastic variable, **indexing with stochastic variable is not supported yet**).
