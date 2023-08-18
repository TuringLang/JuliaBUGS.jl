# BUGS DevMan Notes

## Lexing

- The BUGS language has the convention that if a name is followed
immediately by a round bracket, that is by a "(", then the names is a reserved name in the BUGS
language and does not represent a variable in the model.
- By scanning the stream of tokens that constitute a BUGS language model the names of all the variables in the model can be found.

## A BUGS program is only complete when presented with data

The data will be used in the compilation process, including values of variables and shape of variables.

- Maybe in the future we can support grabbing variables from Julia Runtime

## Table of Names

- The BUGS language compiler expands all the for loops in the model and records the value of the indices of each use of a tensor on the left hand side of each relation.
- The range of each index, for a tensor, is set at the maximum value observed value of the index and added to the name table. There is one exception to this procedure for finding index bounds: names that are data, that is in the data source, have the ranges of their indices fixed in the data source.
- Each scalar and each component of a tensor used on the right hand side of a relation must occur either on the left hand side of a relation and or in a data source.

## Data Transformations

If the compiler can prove that a logical assignment can be evaluated to a constant then the
assignment is called a data transformation. This occurs if an assignment's right hand side does
not depend on any variable quantities. The BUGS language has a general rule that there must only be one assignment statement for each scalar or component of a tensor. This rule is slightly
relaxed for data transformations. The language allows a logical assignment and a stochastic
assignment to the same scalar or tensor component if and only if the logical assignment is a data
transformation. 

- **Possible optimization: do the data transformation first**

## Generated Quantities

Only need to be evaluated after the inference algorithm has finished its task. 

- Generally, these are leaf nodes that logical variables
- In the case of stochastic variables that are leaf nodes, do “forward sampling”, also part of the generated Quantities

## Computation

- All the nodes in the graphical model representing logical relations are placed into an
array and sorted by their nesting level with the first array entries only depending on quantities
defined by stochastic relations. Traversing this array and evaluating nodes gives up to date
values to all logical relations.

## Types

> The BUGS compiler uses the properties of the distribution on the right-hand side of a stochastic assignment statement to make deductions about the variable on the left-hand side. For example, r ~ dbin(p, n) implies that r is integer-valued, while x ~ dnorm(mu, tau) implies that x is real-valued.
> 
> 
> Some distributions are real-valued but have support on a restricted range of the reals. For example, p ~ dbeta(a, b) implies that p is real-valued with support on the unit interval, while x ~ dgamma(r, lambda) implies that x is real-valued but with support on the positive real line.
> 
> There are two multivariate distributions in the BUGS language, the Dirichlet and the Wishart, that have support on a complex subspace of the reals. The Dirichlet has support on the unit simplex, while the Wishart has support on symmetric positive definite matrices.
> 
> The BUGS compiler tries to infer if logical relations return an integer value by looking at whether their parents are integer-valued and the operators that combine the values of their parents into the return value. For example, in the cure model example above, the logical relation state1[i] <- state[i] + 1 is integer-valued because state[i] is a Bernoulli variable and therefore integer, the literal 1 is integer, and the sum of two integers is an integer.
> 
> When the BUGS system reads in data from a data source, it can tag whether the number read is an integer or a real and propagate this information to logical relations. Again, using the cure model as an example, the statement t[i] <- x[i] + y[i] is integer-valued because both x and y are data and are given as integers in the data source.
> 
> One special type of data is constants: that is just numbers with no associated distribution. Constants have many uses in BUGS language models, but one of the most important is as covariates. A model can contain a large number of constants that are used as covariates. Because of the possible large numbers of these covariate-type constants, they are given special treatment by the BUGS compiler. If a name read in from a data source is only used on the right-hand side of logical relations, no nodes in the graphical model are created to hold its values; they are directly incorporated in the objects that represent the right-hand sides of the logical relations.
> 
> For example, the large Methadone model contains the regression:
> 
> mu.indexed[i] <- beta[1] * x1[i] +
> beta[2] * x2[i] +
> beta[3] * x3[i] +
> beta[4] * x4[i] +
> region.effect[region.indexed[i]] +
> source.effect[region.indexed[i]] * source.indexed[i] +
> person.effect[person.indexed[i]]
> 
> where i ranges from 1 to 240776. Not having to create a node in the graphical model to represent x1, x2, x3, x4, region.indexed, source.index, and person.indexed saves a large amount of space.
> 
> In the BUGS language, the type information is fine-grained: each component of a tensor can have different type information. This is quite distinct from the situation in STAN and can make it much easier to specify a statistical model. One common case is where some components of a tensor have been observed while other components need to be estimated. The STAN documentation suggests workarounds for these situations, but these are somewhat complex.
> 
- The type propagation is interesting and maybe useful. But we don’t necessarily need to implement a type system. A dirty way to get type information is simply do a dry run with some tricks.

## Work flow

The statistical model and data are presented to the BUGS system in a series of stages. In the first stage the model text is parsed into a tree and the name table constructed. The data is then loaded and checked against the model. The data can be split over a number of source. Once all the data has been loaded the model is compiled. Compiling builds the graphical model and does a large number of checks on the consistency of the model. Finally initial values can be given or generated for the model.

The compiler creates a node in the graphical model for each scalar name and each component of a tensor name in the BUGS language model. The compiler checks that only one node is created for each scalar name or component of a tensor name.

Reading in a data source causes the compiler to create special nodes called constant nodes to hold the values of the data.

The compiler processes logical relations before stochastic relations. Any logical relations that only have constant nodes on their right hand side become new constant nodes with the appropriate fixed value. Even if a logical relation can not be reduced to a constant some parts of the relation might be reduced to constants.

Any constant nodes that have an associated stochastic relation become data nodes in the graphical model.

# Logical relations in the BUGS Language

The OpenBUGS software compiles a description of a statistical model in the BUGS language
into a graph of objects. Each relation in the statistical model gives rise to a node in the graph of
objects. Each distinct type of relation in the statistical model is represented by a node of a
distinct class. For stochastic relations there is a fixed set of distributions that can be used in the
modelling. For logical relations the situation is more complex. The software can use arbitrary
logical expressions build out of a fixed set of basic operators and functions. For each distinct
logical expression a new software source code module is written to implement a class to
represent that logical expression in the graph of objects. The software module is then compiled
using the Components Pascal compiler and the executable code merged into the running
OpenBUGS software using the run time loading linker.

The BUGS language description of a statistical model is parsed into a list of trees. The sub-trees
that represent logical relations in the statistical model are first converted into a stack based
representation and then into Component Pascal source code. The source code is generated in
module BugsCPWrite and the source code is then compiled in module BugsCPCompiler.
Usually the generated source code is not displayed. Checking the Verbose option in the Info
menu will cause each each source code module generated by the OpenBUGS software to be
displayed in a separate window.

One advantage of a stack based representation of an expression is that it is straight forward to
use it to derive source code that calculates the derivative of the expression with respect to its
arguments. This part of the source code generation is carried out in module BugsCPWrite in
procedure WriteEvaluateDiffMethod. Each operator in the stack representation of the logical
expression causes a snippet of Component Pascal code to be written. These code snippets are
generally very simple with those of binary operators slightly more complex than those of unitary
operators. Each binary operators can emit three different code snippets: the general case and
two special snippets depending on whether the left or right operands are numerical constants.
The only complex code snippet is when an operand that is a logical relation in the statistical model is pushed onto the stack -- the case of nested logical relations. In this case the nested
logical relation will have its own code to calculate derivatives and these values can be passed up
the nesting level.

The OpenBUGS software now uses a backward mode scheme to calculate the value of logical
nodes in the statistical model. All the logical nodes in the statistical model are held in a global
array and sorted according to their nesting level with unnested nodes at the start of the array. To
evaluate all the logical nodes in the statistical model this array is then traversed and each logical
node evaluated and the value stored in the node. The same scheme is used to calculate
derivatives.

The graphs derived from the BUGS language representation of statistical models are generally
sparse. The OpenBUGS software uses conditional independence arguments to exploit sparsity
in the stochastic parts of the model. There is also a sparsity structure in logical relations.Each
logical relation will often depend on just a few stochastic parents and derivatives with respect to
other stochastic nodes in the model will be structurally zero. Each logical node has an associated
array of stochastic parents for which the derivatives are non zero. Moving up the level of nesting
the number of parents can grow. Dealing with this issue leads to the complexity in the code
snippet for the operator that pushes a logical node onto the stack. These issues can be seen in
the non-linear random effects model called Orange trees in volume II of the OpenBUGS
examples. In this model eta[i,] is a function of phi[i,1], phi[i,2] and phi[i,3] where the phi are also
logical functions of the stochastic theta[i,].

One refinement of the backward mode scheme used to calculate the value of logical nodes is to
consider separately any logical nodes in the statistical model which are only used for prediction
and do not affect the calculation of the joint probability distribution. These nodes need only be
evaluated once per iteration of the inference algorithm. Examples of such nodes are sigma[k]
and sigma.C in the Orange trees example. There is no need to evaluate the derivatives of these
prediction nodes.

The workings of the backward mode scheme are easy to visualize when the inference algorithm
updates all the stochastic nodes in the statistical model in one block. Local versions of the
backward mode scheme can be used when the inference algorithm works on single nodes or
when a small blocks of nodes are updated. Each stochastic node is given its own vector of
logical nodes that depend on it either directly or via other logical nodes and this vector is sorted
by nesting level. Each updater that works on small blocks of nodes contains a vector of logical
nodes which is the union of the vectors of dependent logical nodes for each of its components.

The idea of the backward mode scheme for evaluating logical nodes can be used with caching in
Metropolis Hastings sampling. First the vector of logical nodes depending on the relevant
stochastic node(s) is evaluated and their values cached. The log of the conditional distribution is
then calculated. Next a new value of the stochastic node is proposed. The vector of logical nodes is re-evaluated and the log of the conditional distribution calculated. If the proposed value is
rejected then the cache is used to set the vector of logical nodes back to its old values.

The OpenBUGS software also calculates what class of function each logical node is in terms of
its stochastic parents. If the software can prove for example that a logical node is a linear function
of its parents more efficient sampling algorithms can be used. If a linear relation can be proved
then the calculation of derivatives can also be optimized in some cases because they will be
constant and so only need to be calculated once. Generalized linear models are implemented in
a way that allows fast calculation of derivatives. The structure of the algorithm to classify the
functional form of logical nodes is very similar to that for derivatives and uses a backward mode
scheme

BUGS separates management of logical and stochastic variables, essentially two graphs. Logical variables are stored in an array and values are updated with values in earlier positions of the array.

# Blurred Line Between Data and Observed Stochastic Variables
One subtle and maybe debatable aspect of `BUGS`' syntax is that the value(observation) of an observed stochastic variable is the same as any model parameters provided in the `data`.
For instance, the following program is legal.
```R
model {
    N ~ dcat(p[])
    for (i in 1:N) {
        y[i] ~ dnorm(mu, tau)
    }
    p[1] <- 0.5
    p[2] <- 0.5
}
```
For an observation to be used in loop bounds or indexing, it must be included in the given `data`, not a transformed variable.
The current version of `JuliaBUGS` is consistent with this behavior, although the earlier `SymbolicPPL` disallows this.  
It is possible to implement this check in `JuliaBUGS`. For a naive implementation, we can just invalidate(e.g. mark as `missing`) all observations after the first pass, and check if any of them are used in loop bounds or indexing. But at this time, we don't have plan to implementing this check.
