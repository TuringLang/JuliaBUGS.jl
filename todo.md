## The pass interface
The pass interface should be more flexible and composable. 
For instance, we can further abstract out the `assignment!` function and defined an interface called `action` and define artifact of the `action`, so that we can compose different actions together -- in the same pass, parallel actions can be done at once


## Useful passes
- analysis variable transformation `bijectors`
- conjugate analysis
- discrete variable marginalization
- state-space model detection
- Gaussian network detection or marginalization
- symbolic simplification -- because we have the graph, we don't need to store all the symbolic expressions, can create them in time. (this actually include exact inference)

## Compilation target:
- a Distributions.Distribution
- logdensity([], trace, model)

## Possible extension of semantics:
- allow the use of variable defined before the current line (should be useful, while don't need to do a whole scope analysis)
- mutation should still be banned -- this is a analysis thing

## Node functions
A complication arises when the rhs of a tilde function can evaluate to different types of distributions, this has implications on the variable type, the transformation needed and even what the model means. 
Also, as we discussed, the node function can also be Turing model, which makes thing potentially more complicated.

**For now, the target is to run BUGS model, so keep things simple.**

* autodiff and logdensityproblems

# Combine symbolic compiler with JuliaBUGS
* 