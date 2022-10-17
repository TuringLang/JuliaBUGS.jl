# SymbolicPPL.jl

This package contains some infrastructure to work with graphical probabilistic models in symbolic form, consisting of a model DSL (which one could call "frontend"), an attempt of its formalization (ongoing work), and AbstractPPL-compatible evaluation facilities (i.e., sampling and density evaluation, conditioning, etc.).

## Caution!

This implementation should be able to parse existing BUGS models and run them. It is, however, still a bit sketchy and not yet ready for serious work.  

We are (as of autumn 2022) planning to continually keep working on this project, until we have a mature BUGS-compatible graphical PPL system integrated in the Turing ecosystem.

## Example: Logistic Regression with Random Effects
We will use the [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) model for demonstration. 
The example concerns the proportion of seeds that germinated on each of 21 plates. The data is (rewritten in Julia's NamedTuple)

```julia
data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)
```
 
where `r[i]` is the number of germinated seeds and `n[i]` is the total number of the seeds on the $i$-th plate. 
The model is constructed such that, let $p_i$ be the probability of germination on the $i$-th plate, 

$$
\begin{aligned}
r_i &\sim \operatorname{Binomial}(p_i, n_i) \\
\operatorname{logit}(p_i) &\sim \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
b_i &\sim \operatorname{Normal}(0, \tau)
\end{aligned}
$$

where $x_{1i}$ and $x_{2i}$ are the seed type and root extract of the $i$-th plate.  
The original BUGS program for the model is 
```
model
{
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma <- 1 / sqrt(tau)
}
```

## Modeling Language
References:  
 - [MultiBUGS](https://www.multibugs.org/documentation/latest/)
 - [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)
### Writing Model in Julia
We provide a macro solution which allows users to write down model definitions using Julia:

```julia
@bugsast begin
    for i in 1:N
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma = 1 / sqrt(tau)
end
```
BUGS syntax carries over almost one-to-one to Julia. 
The only change is regarding the link functions, we encourage users to call the inverse function on the RHS instead of the original BGUS-style syntax. 
The concern is that Julia use the "function call on LHS"-like syntax as a shorthand for function definition. 
Thus the BUGS-style link function syntax is likely to cause confusion for Julia users.

### Support for Lagacy BUGS Programs
We also provide a string macro `bugsmodel` to work with original (R-like) BUGS syntax:

```julia
bugsmodel"""
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma <- 1 / sqrt(tau)
"""
```

This is simply the unmodified code in the `model { }` enclosure.  
We encourage users to write new program using the Julia-native syntax, because of better debuggability and perks like syntax highlighting. 

## Compilation

### Compilation Interface
The main function for compilation is 

```julia
compile(model_def::Expr, data::NamedTuple) # compile a BUGSGraph object without initialization
compile(model_def::Expr, data::NamedTuple, inits::NamedTuple) # compile a BUGSGraph object with initializations
compile(model_def::Expr, data::NamedTuple, inits::Vector{NamedTuple}) # compile a vector of BUGSGraph object with initializations
```

so to compile the model definition given above, 

```julia-repo
# model_def is the julia AST generate by `@bugsast` or `bugsmodel`
julia> model = compile(model_def, data); 

julia> typeof(model)
BUGSGraph
```

### Compilation Target
As you can see, the result of the compilation is an object of the type `BUGSGraph`.
There are three major components of a `BUGSGraph` object: [Graphs.DiGraph](https://juliagraphs.org/Graphs.jl/dev/core_functions/module/#Graphs.DiGraph) for graph structure, node functions for all the variables in the DAG, and whether a variable is observed or assumed.

#### The DAG
User can retrieve the [Graphs.DiGraph](https://juliagraphs.org/Graphs.jl/dev/core_functions/module/#Graphs.DiGraph) object with
```julia-repo
julia> dag = getDAG(model)
{47, 89} directed simple Int64 graph
```
All nodes in the DAG is aliased with an integer number. 
To look up the integer alias of a variable, user can use function

```julia-repo
julia> nodealias(model, @nn r[1]) # equivalently getnodeenum(model, Symbol("r[1]"))
3 
```

Please note, if a variable is an array indexing, e.g., `g[2, 3]`, the blank in front of `3` is important. 
We provide the macro `@nn` to facilitate formatting array indexings.

```julia-repo
julia> @nn g[2,3]
Symbol("g[2, 3]")
```

A reverse lookup function is also provided.

```julia-repo
julia> nodename(model, 3)
Symbol("r[1]")
```

Other useful functions include

```julia
numnodes(g::BUGSGraph) # return number of nodes
getsortednodes(g::BUGSGraph) # return nodes in topological order
parents(g::BUGSGraph, node::Integer) # return the parents of the node
chidren(g::BUGSGraph, node::Integer) # return the children of the node
markovblanket(g::BUGSGraph, node::Integer) # return the Markov Blanket of the node
```

#### Node Functions
Every node in the graph corresponds to a stochastic variable from the original program.
The node function of a node is a function such that, when evaluated given the node's parents' value, will return a [Distributions.Distribution](https://github.com/JuliaStats/Distributions.jl) object.

User can use `shownodefunc` to print out the node function

```julia-repo
julia> shownodefunc(model, 3)
Parent Nodes: alpha0, b[1]
Node Function: begin
    (SymbolicPPL.dbin)((/)(1, (+)(1, (exp)((+)((+)(0, (*)(-1, alpha0)), (*)(-1, var"b[1]"))))), 39)
end
```

This may not be expected from the model definition, but after substituting the data in one can verify that it is a correct. This simplification is powered by the symbolic algebra system we use during the compilation.

User can use `rand(model::BUGSModel)` to generate a random trace of the program and `getdistribution(model::BUGSModel, node::Integer, value::Vector{Integer})` to get the distribution of the node evaluated with the program trace. 
```julia-repo
julia> value = rand(model);

julia> getdistribution(model, 3, value)
Distributions.Binomial{Float64}(n=39, p=0.0)
```

where `value` is a `Vector` indexed by nodes' integer alias.

#### Debug Model
User can choose compile to a `CompilerState` object and check the corresponding expression for a variable using 

```julia-repo
julia> model_cs = compile_inter(model_def, data);

julia> querynode(model_cs, @nn r[1])
SymbolicPPL.dbin(p[1], n[1])
```

### Supported BUGS Distribution and Functions
The library of supported BUGS distributions and utility functions is still growing in the current version. 
User can register their own distributions and functions with the macros

```julia-repo
julia> # Should be restricted to pure function that do simple operations
@primitive function f(x)
    return x + 1
end

julia> SymbolicPPL.f(2)
3
```

, and 

```julia-repo
julia> # Need to return a Distributions.Distribution 
@primitive function d(x) 
    return Normal(0, x^2)
end true # if the second argument is specified to be true, then add distribution

julia> SymbolicPPL.d(1)
Distributions.Normal{Float64}(μ=0.0, σ=1.0)
```

After registering the function or distributions, they can be used just like any other functions or distributions provided by BUGS.  
Please use these macros cautiously as they may cause name clashes and potential breaking behaviors.

### Inference
#### Native Graph-Based Inference Algorithms
We plan to implement a library of high performance graph-based inference algorithms in the future. Contributions are welcome and much appreciated. Interested contributors can check out the [implementation](https://github.com/TuringLang/SymbolicPPL.jl/blob/use_graphs/src/gibbs.jl) of a very simplistic [AbstractMCMC.jl](https://github.com/TuringLang/AbstractMCMC.jl) Metropolis-within-Gibbs sampler for interface references. 

#### Using Inference Infrastructure from [Turing.jl](https://github.com/TuringLang/Turing.jl)
Users who want to run BUGS program right now can try out the `toTuring` function, which will compile the `BUGSGraph` object to a `Turing.Model`.

**Caution**: `toTuring` is not yet well tested and we can't guarantee its correctness, bugs reports are welcomed.

```julia-repo
julia> m = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(b, a^2)
end; 

julia> g = compile(m, (a=1, b=2)); 

julia> model = toTuring(g);

julia> rand(model())
(c = 2.2019001981565207,)
```

User can also check the input to Turing's compiler by 

```julia-repo
julia> inputtoTuring(g)
:(function bugsturing(; b = 2, a = 1)
      a ~ Normal(0.0, 1.0)
      b ~ SymbolicPPL.dnorm(a, 1)
      c ~ SymbolicPPL.dnorm(b, a ^ 2)
  end)
``` 
