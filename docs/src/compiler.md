# Compilation 


The compilation pipeline of the SymbolicPPL compiler is:
    1. transform the AST produced by `@bugsast` (and `@bugsmodel`) further to facilitate downstream processing. 
    2. iteratively unroll and add logical rules, then add stochastic rules
    3. generate `BUGSGraph` from `CompilerState`




