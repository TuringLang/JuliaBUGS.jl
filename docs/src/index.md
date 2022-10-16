# Introduction
SymbolicPPL is a graph-based probabilistic programming language. 
The syntax is similar to BUGS(Bayesian inference Using Gibbs Sampling) and the package also has the ability to run existing BUGS program.

The package has three major pieces: 
    - translate BUGS programs and SymbolicPPL programs into Julia AST (the frontend)
    - process the Julia AST and generate a graph representation (the backend)
    - do Bayesian inference (inference) 

## Frontend
Implementation detail and use directions can be found at the (ast transformation guide)[]. 

## Backend
SymbolicPPL (and BUGS) programs contain two kinds of assignments: logical and stochastic. 
Different from the common programming languages that are expected to be executed in order, the assignments describe edges in DAGs, thus can be arranges in any order.  

A direct result of this is: to decide if an expression contains a stochastic variable, the compiler program need to check all the assignments in the program definition. 

As it turns out that, to guarantee the finiteness of the compiled graph representation, the compiler needs to check and make sure that no loop bounds and array indices are dependent on stochastic variables.

By transfer the task of determining if an expression is dependent on a stochastic variable to check whether the expression can be evaluated to a number given that the program input is complete, we use [Symbolics.jl]() heavily in our compiler implementation. 

By processing logical assignments and data as substitution rules, we can determine if any expression can be reduced to a concrete real number. Then forcing the reducible-to-real property on all the loop bounds and array indices can guarantee that SymbolicPPL/BUGS programs can be compiled to a DAG.

Introducing symbolic algebra system brings another great benefits: simplification. The naive transformation from SymbolicPPL/BUGS program to DAG representation will introduce a node for every variable and an edge for every assignment. The two major drawback of this approach are: *(1)* the DAG can be unnecessarily large, and *(2)* inference algorithms on graph often need to modify the value of variables, but propagating the value changes and determining the markov blankets can be tricky with complex logical nodes in between stochastic nodes. 

With the symbolic algebra system, the SymbolicPPL compiler is able to "absorb" all the logical nodes to the child stochastic nodes, so that, when a "node function" is evaluated with the values of its parents, will return a Distribution object just like before. 

## Inference


