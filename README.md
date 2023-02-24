# JuliaBUGS.jl

This package contains some infrastructure to work with graphical probabilistic models in symbolic form, consisting of a model DSL (which one could call "frontend"), an attempt of its formalization (ongoing work), and AbstractPPL-compatible evaluation facilities (i.e., sampling and density evaluation, conditioning, etc.).

## Caution!

This implementation should be able to parse existing BUGS models and run them. It is, however, still in its very early stage and not yet ready for serious work.  

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
Language References:  
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
The only change is regarding the link functions in logical assignments.
Because Julia uses the "function call on LHS"-like syntax as a shorthand for function definition, BUGS' link function syntax can be unidiomatic and confusing.
We adopt a more Julian syntax as demonstrated in the model definition above: instead of calling the link function, we call the inverse link function from the RHS. However, the Julian link function semantics internally is equivalent to the BUGS. 

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

### Using Self-defined Functions and Distributions
User can register their own functions and distributions with the macros

```julia-repo
julia> # Should be restricted to pure function that do simple operations
@register_function function f(x)
    return x + 1
end

julia> JuliaBUGS.f(2)
3
```

, and 

```julia-repo
julia> # Need to return a Distributions.Distribution 
@register_distribution function d(x) 
    return Normal(0, x^2)
end 

julia> JuliaBUGS.d(1)
Distributions.Normal{Float64}(μ=0.0, σ=1.0)
```

After registering the function or distributions, they can be used just like any other functions or distributions provided by BUGS. 

Please use these macros with caution to avoid causing name clashes. Such name clashes would override default BUGS primitives and cause breaking behaviours.

## Compilation

The main function for compilation is 

```julia
compile(model_def::Expr, data::NamedTuple, target::Symbol),
```

which takes three arguments: 
- the first argument is the output of `@bugsast` or `bugsmodel`, 
- the second argument is the data 
- the third argument is a `Symbol` indicating the compilation target.

To compile the `Seeds` model to a conditioned `Turing.Model`, specify the target to be `:DynamicPPL`

```julia-repo
julia> model = compile(model_def, data, :DynamicPPL); 

```

## Inference

Once compiled to a `Turing.Model`, user can choose [inference algorithms](https://turing.ml/dev/docs/library/) supported by Turing. Here we use `NUTS` for demonstration, 

```julia-repo
julia> using Turing; chn = sample(model(), NUTS(), 11000, discard_initial = 1000);

julia> chn[[:alpha0, :alpha1, :alpha12, :alpha2, :tau]]
Chains MCMC chain (11000×5×1 Array{Float64, 3}):

Iterations        = 1001:1:12000
Number of chains  = 1
Samples per chain = 11000
Wall duration     = 22.11 seconds
Compute duration  = 22.11 seconds
parameters        = alpha1, alpha12, alpha2, tau, alpha0
internals         = 

Summary Statistics
  parameters      mean       std   naive_se      mcse         ess      rhat   ess_per_sec 
      Symbol   Float64   Float64    Float64   Float64     Float64   Float64       Float64 

      alpha1    0.0842    0.3131     0.0030    0.0051   4329.1277    1.0004      195.7995
     alpha12   -0.8335    0.4398     0.0042    0.0062   4528.4134    0.9999      204.8129
      alpha2    1.3542    0.2773     0.0026    0.0043   4101.1509    1.0001      185.4885
         tau   32.2479   63.7739     0.6081    3.0866    337.8219    1.0016       15.2791
      alpha0   -0.5510    0.1937     0.0018    0.0031   4297.2842    1.0000      194.3593

Quantiles
  parameters      2.5%     25.0%     50.0%     75.0%      97.5% 
      Symbol   Float64   Float64   Float64   Float64    Float64 

      alpha1   -0.5437   -0.1164    0.0875    0.2852     0.7015
     alpha12   -1.7463   -1.1118   -0.8265   -0.5452     0.0110
      alpha2    0.8301    1.1752    1.3467    1.5263     1.9199
         tau    2.8413    7.0837   12.4850   26.2675   226.2762
      alpha0   -0.9384   -0.6731   -0.5493   -0.4286    -0.1649
```

One can verify the inference result is coherent with BUGS' result for [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) (here we reported `tau` instead of `sigma` with `sigma = 1 / sqrt(tau)`). 
The output of `sample` is a [`Chains`](https://turinglang.github.io/MCMCChains.jl/stable/chains/) object, and visualizating of the results is easy to produce,  

```julia-repo
julia> using StatsPlots; plot(chn[[:alpha0, :alpha1, :alpha12, :alpha2, :tau]]);

```

With default settings, we get

![seeds](https://user-images.githubusercontent.com/5433119/198809451-6a9a2974-6015-4a6e-8508-a6e7dd35116f.svg)

## More Compilation Target
**Work in Progress: the interface can change drastically**

User can also compile the model into a DAG by specifying the target to be `:Graph`.

```julia-repo
julia> g = compile(model_def, data, :Graph); 

```

returns a [MetaDiGraph](https://juliagraphs.org/MetaGraphsNext.jl/dev/api/#MetaGraphsNext.MetaDiGraph).
And every vertex in the graph corresponds to a stochastic variable, for example the variable `r[2]` 

```julia-repo
julia> g[Symbol("r[2]")]
Variable Name: r[2]
Variable Type: Observation
Data: 23
Parent Nodes: alpha0, b[2]
Node Function: JuliaBUGS.dbin(1 / (1 + exp(-alpha0 - b[2])), 62)
```

`Node Function` is a function that produces a distribution given the values of parents stochastic variables.

Compare the `Node Function` of `r[2]` with the original definition, we can see it has been largely simplified, thanks to [Symbolics.jl](https://symbolics.juliasymbolics.org/dev/) that we use internally. 

## Specifying Finite Mixture Models 
- Stochastic indexing
- use `@register_distribution` to register function that take the indexing variable and other variables required to parametrize intended distributions

## More Examples
We have transcribed all the examples from the first volume of the BUGS Examples ([origianl](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/master/src/BUGSExamples/Volume_I)). All the programs and data are included, and they can be compiled in a similar way as we have demonstrated before.
