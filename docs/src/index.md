# Introduction
SymbolicPPL is a graph-based probabilistic programming language that's part of the Turing ecosystem. 
The syntax of SymbolicPPL is based on [BUGS](https://www.mrc-bsu.cam.ac.uk/software/bugs/). 
The package also has the ability to run existing BUGS programs.

For now, please refer to the [Github project page](https://github.com/TuringLang/SymbolicPPL.jl) for usage information and a complete example.

We encourage user of the BUGS language first construct a model on paper. 
Each variable in a program in BUGS language defines a stochastic variable or a shorthand relation. 
The stochastic variables will be translated to a node in a directed graphical model. 
And a tilde relation will be translated to a directed edge in the graphical model.

Users who familiar with programming language like Julia should be warned that the array and loop syntax in BUGS is different from Julia. 
In BUGS, loops do not represent the control flow, but a shorthand (a easier way) to write programs for the unrolled version of the program.
