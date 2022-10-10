# SymbolicPPL.jl

This package contains some infrastructure to work with graphical probabilistic models in symbolic form, consisting of a model DSL (which one could call "frontend"), an attempt of its formalization (ongoing work), and AbstractPPL-compatible evaluation facilities (i.e., sampling and density evaluation, conditioning, etc.).

## Caution!

This implementation should be able to parse existing BUGS models and run them. It is, however, still a bit sketchy and not yet ready for serious work.  

We are (as of autumn 2022) planning to continually keep working on this project, until we have a mature BUGS-compatible graphical PPL system integrated in the Turing ecosystem.

## Modeling Language

### Writing New Models
We provide a macro solution which allows to directly use Julia code corresponding to BUGS code:

```julia
@bugsast begin
    for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - x̄)
    end
    τ ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1e-6)
    β = dnorm(0.0, 1e-6)
end
```
BUGS syntax carries over almost one-to-one to Julia.

### Lagacy BUGS Programs
We provide a string macro `bugsmodel` to work with original (R-like) BUGS syntax:

```julia
bugsmodel"""
    for (i in 1:5) {
        y[i] ~ dnorm(mu[i], tau)
        mu[i] <- alpha + beta*(x[i] - mean(x[]))
    }
    
    alpha ~ dflat()
    beta ~ dflat()
    tau <- 1/sigma2
    log(sigma2) <- 2*log.sigma
    log.sigma ~ dflat()
"""
```

This is simply the unmodified code in the `model { }` enclosure.  
We encourage users to write new program using the Julia-native syntax, because of better debuggability and perks like syntax highlighting. 

## Compilation
### Compilation Target
There are three major components of the compilation result: [Graphs.DiGraph](https://juliagraphs.org/Graphs.jl/dev/core_functions/module/#Graphs.DiGraph) for graph structure, node functions for all the variables in the DAG, and whether a variable is observed or assumed.

#### The DAG
User can retrieve the [Graphs.DiGraph](https://juliagraphs.org/Graphs.jl/dev/core_functions/module/#Graphs.DiGraph) object with
```julia
getDAG(g::BUGSGraph)
```
All nodes in the DAG is aliased with an integer number. 
To look up the integer alias of a variable, user can use function

```julia
getnodeenum(g::BUGSGraph, node::Symbol).
```

Please note, if a variable is an array indexing, e.g., `g[2, 3]`, the blank in front of `3` is important. 
Alternatively, we also provide a macro `@nodename` to facilitate formatting.

```julia-repo
julia> @nodename g[2,3]
Symbol("g[2, 3]")
```

A reverse lookup function is also provided.

```julia
getnodename(g::BUGSGraph, node::Integer)
```

Other useful functions include

```julia
getnumnodes(g::BUGSGraph) # return number of nodes
getsortednodes(g::BUGSGraph) # return nodes in topological order
getparents(g::BUGSGraph, node::Integer)
getchidren(g::BUGSGraph, node::Integer)
getmarkovblanket(g::BUGSGraph, node::Integer) 
```

#### Node Functions
Every node in the graph corresponds to a stochastic variable from the original program.
The node function of a node is a function such that, when evaluated given the node's parents' value, will return a [Distributions.Distribution](https://github.com/JuliaStats/Distributions.jl) object.

User can use `shownodefunc` to print out the node function

```julia
shownodefunc(g::BUGSGraph, node::Integer)
```

and 
```julia
getdistribution(g::BUGSGraph, node::Integer, value::Vector{Real}) 
```

to get the distribution object given the values of all the nodes.

### Compilation Interface
The main function for compilation is 

```julia
compile(model_def::Expr, data::NamedTuple) # compile a BUGSGraph object without initialization
compile(model_def::Expr, data::NamedTuple, inits::NamedTuple) # compile a BUGSGraph object with initializations
compile(model_def::Expr, data::NamedTuple, inits::Vector{NamedTuple}) # compile a vector of BUGSGraph object with initializations
```

User can also compile to a intermediate representation, a `CompilerState` object and check the corresponding expression for a variable using 

```julia
querynode(compiler_state::CompilerState, var::Symbol)
```

### Supported BUGS Distribution and Functions
The library of supported BUGS distributions and utility functions are limited in the current version. 
User can register them own distributions and functions with the macros

```julia
# Should be restricted to pure function that do simple operations
@bugsfunction function f(x)
    return x + 1
end
```

, and 

```julia
# Need to return a Distributions.Distribution 
@bugsdistributions function d(x)
    return Normal(0, x^2)
end
```

Please use these macros cautiously. 

### Inference
#### Native Graph-Based Inference Algorithms
We plan to implement a library of high performance graph-based inference algorithms in the future. Contributions are welcome and much appreciated. Interested contributors can check out the [implementation](https://github.com/TuringLang/SymbolicPPL.jl/blob/use_graphs/src/gibbs.jl) of a very simplistic Metropolis-within_Gibbs sampler for interface reference.

#### Using Inference Infrastructure from [Turing.jl](https://github.com/TuringLang/Turing.jl)
Users who want to run BUGS program right now can try out the `toturing` function, which will compile the `BUGSGraph` object to a `Turing.Model`.

**Caution**: `toturing` is not yet well tested and we can't guarantee its correctness, bugs reports are welcomed.

```julia-repo
julia> model = toturing(g::BUGSGraph) # model is a Turing.Model
```
User can also check the input to Turing's compiler by 

```julia
inspect_toturing(g::BUGSGraph)
``` 
