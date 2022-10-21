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
        @link_function logit p[i] = alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
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
The only change is regarding the link functions.
Because Julia uses the "function call on LHS"-like syntax as a shorthand for function definition, BUGS' link function syntax can be unidiomatic and confusing.
We adopt a macro syntax as demonstrated in the model definition above: instead of calling the link function, make link function the first argument to the macro.  

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

julia> SymbolicPPL.f(2)
3
```

, and 

```julia-repo
julia> # Need to return a Distributions.Distribution 
@register_distribution function d(x) 
    return Normal(0, x^2)
end true 

julia> SymbolicPPL.d(1)
Distributions.Normal{Float64}(μ=0.0, σ=1.0)
```

After registering the function or distributions, they can be used just like any other functions or distributions provided by BUGS.  
**Caution** Please use these macros cautiously as they may cause name clashes and potential breaking behaviors.

## Compilation

The main function for compilation is 

```julia
compile(model_def::Expr, data::NamedTuple, target::Symbol),
```

which takes three arguments: 
- first argument is the output of `@bugsast` or `bugsmodel`, 
- second argument is the data 
- third argument is a `Symbol` indicating the output of the compilation. 

To compile the `Seeds` model to a conditioned `Turing.Model`,  

```julia-repo
julia> model = compile(model_def, data, :DynamicPPL); 

```

## Inference

Once compiled to a `Turing.Model`, user can choose inference algorithm supported by [`Turing.jl`](https://turing.ml/dev/docs/library/).

```julia-repo
julia> using Turing; chn = sample(model(), HMC(0.1, 5), 100000);

julia> using StatsPlots; plot(s)

