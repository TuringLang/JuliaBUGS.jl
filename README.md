# SymbolicPPL.jl

This package contains some infrastructure to work with graphical probabilistic models in symbolic form, consisting of a model DSL (which one could call "frontend"), an attempt of its formalization (ongoing work), and AbstractPPL-compatible evaluation facilities (i.e., sampling and density evaluation, conditioning, etc.).

## Caution!

This implementation should be able to parse existing BUGS models and run them. It is, however, still in its very early stage and not yet ready for serious work.  

We are (as of autumn 2022) planning to continually keep working on this project, until we have a mature BUGS-compatible graphical PPL system integrated in the Turing ecosystem.

**Nested indexing with stochastic variable is not supported. In BUGS, this language feature is most often used to write mixture models, for an example, refer to [Eyes](https://www.multibugs.org/examples/latest/Eyes.html). Nested indexing with data is supported otherwise.**

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

julia> SymbolicPPL.f(2)
3
```

, and 

```julia-repo
julia> # Need to return a Distributions.Distribution 
@register_distribution function d(x) 
    return Normal(0, x^2)
end 

julia> SymbolicPPL.d(1)
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

To compile the `Seeds` model to a conditioned `Turing.Model`,  

```julia-repo
julia> model = compile(model_def, data, :DynamicPPL); 

```

## Inference

Once compiled to a `Turing.Model`, user can choose [inference algorithms](https://turing.ml/dev/docs/library/) supported by Turing. Here we use `HMC` for demonstration, 

```julia-repo
julia> using Turing; chn = sample(model(), HMC(0.1, 5), 12000, discard_initial = 1000);

julia> chn[[:alpha0, :alpha1, :alpha12, :alpha2, :tau]]
Chains MCMC chain (12000×5×1 Array{Float64, 3}):

Iterations        = 1001:1:13000
Number of chains  = 1
Samples per chain = 12000
Wall duration     = 8.87 seconds
Compute duration  = 8.87 seconds
parameters        = alpha1, alpha12, alpha2, tau, alpha0
internals         = 

Summary Statistics
  parameters      mean       std   naive_se      mcse         ess      rhat   ess_per_sec 
      Symbol   Float64   Float64    Float64   Float64     Float64   Float64       Float64 

      alpha1    0.0782    0.3112     0.0028    0.0079   1537.3193    0.9999      173.3754
     alpha12   -0.8223    0.4356     0.0040    0.0120   1287.7594    0.9999      145.2306
      alpha2    1.3496    0.2764     0.0025    0.0068   1611.5933    0.9999      181.7518
         tau   27.2953   45.8652     0.4187    3.5472     90.5342    1.0077       10.2102
      alpha0   -0.5524    0.1969     0.0018    0.0042   1908.2302    1.0001      215.2058

Quantiles
  parameters      2.5%     25.0%     50.0%     75.0%      97.5% 
      Symbol   Float64   Float64   Float64   Float64    Float64 

      alpha1   -0.5283   -0.1172    0.0808    0.2873     0.6788
     alpha12   -1.7122   -1.1049   -0.8147   -0.5458     0.0241
      alpha2    0.8160    1.1761    1.3404    1.5205     1.9120
         tau    2.4891    6.6951   12.0090   24.4123   159.0162
      alpha0   -0.9477   -0.6790   -0.5507   -0.4268    -0.1586
```

One can verify the inference result is coherent with BUGS' result for [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) (here we reported `tau` instead of `sigma` with `sigma = 1 / sqrt(tau)`). 
The output of `sample` is a [`Chains`](https://beta.turing.ml/MCMCChains.jl/stable/chains/) object, and visualization the results is easy,  

```julia-repo
julia> using StatsPlots; plot(chn[[:alpha0, :alpha1, :alpha12, :alpha2, :tau]]);

```

With default settings, we get

![seeds](https://user-images.githubusercontent.com/5433119/197317818-580f66c4-3f49-4204-8e8c-e149906d73df.svg)

## More Examples
We have transcribed all the examples from the first volume of the BUGS Examples, they can be find [here](https://www.multibugs.org/examples/latest/VolumeI.html). All the programs and data are included, and they can be compiled in a similar way as we have demonstrated before.
