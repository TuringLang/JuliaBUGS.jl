
Here we implement the dependency graph and source generation discussed in 4.

## Separate the source generation into two steps for clarity and reuse

### Lowering BUGS program to distinguish `observation`s and `model parameters`s

Because the code for observations and model parameters are different, it makes sense to introduce a new type of statements to distinguish between the two types.
To this end, I decided that `≂`(`\eqsim`) is a good choice.

So the new syntax becomes something like
```julia
@bugs begin
    a = b + 1 # deterministic
    a ~ Normal() # model parameters
    a ≂ Normal() # observations
end
```
later we can work on exposing this to user to directly translate programs like this into a log density computation function.

## Transform (some) BUGS programs into the lowered form

The algorithm to do this is discussed in 4.
To summarize, we need to build a statement dependency graph. The graph can be obtained by merging all vertices associated with each statement.
If the dependency graph doesn't contain loops. We can reorder the statements according to the topological order of the dependency graph.
To reorder, we first need to perform complete loop fissions, because the dependency graph is a coarse grain graph whose node representing _all_ the computations associated with each statement. 
If all vertices (variables) associated with a particular statement are all of the same type (deterministic, observations, or model parameters), then we can generate a log density computation function by program transformation.


