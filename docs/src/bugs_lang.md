# BUGS Language Reference (Under Construction)
For now please refer to [Model Specification](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html).

## Notes on Modeling with BUGS
We encourage users of the BUGS language first construct a model on paper. 

Every stochastic variable corresponds to a node in the graph, and every tilde assignment corresponds to the node's incoming edges. 
The compiler will eagerly replace all the logical variables with their corresponding assignment. 
Thus the compiled graph only contains stochastic variables.

Users familiar with programming languages like Julia should be warned that BUGS's array and loop syntax differs from Julia's. 
In BUGS, loops do not represent the control flow but a shorthand to write programs for the unrolled version of the program.