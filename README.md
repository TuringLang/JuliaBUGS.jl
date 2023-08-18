# JuliaBUGS.jl

A modern implementation of the BUGS probabilistic programming language in Julia. 

## Caution!

This is still a work in progress and may not be ready for serious use.

## Example: Logistic Regression with Random Effects
We will use the [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) model for demonstration. 
This example concerns the proportion of seeds that germinated on each of 21 plates. Here, we transform the data into a `NamedTuple`:

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
Let $p_i$ be the probability of germination on the $i$-th plate. Then the model is defined by:

$$
\begin{aligned}
r_i &\sim \text{Binomial}(p_i, n_i) \\
\text{logit}(p_i) &\sim \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
b_i &\sim \text{Normal}(0, \tau)
\end{aligned}
$$

where $x_{1i}$ and $x_{2i}$ are the seed type and root extract of the $i$-th plate.  
The original BUGS program for the model is:
```R
model
{
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
        alpha12 * x1[i] * x2[i] + b[i]
    }
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tau)
}
```

## Modeling Language

### Writing a Model in BUGS
BUGS language syntax: [BNF definition](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/archive/parser_attempts/BNF.txt)

Language References:  
 - [MultiBUGS](https://www.multibugs.org/documentation/latest/)
 - [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)

Implementations in C++ and R:
- [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and its [user manual](https://people.stat.sc.edu/hansont/stat740/jags_user_manual.pdf)
- [Nimble](https://r-nimble.org/)

### Writing a Model in Julia
We provide a macro solution which allows users to write down model definitions using Julia:

```julia
@bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        b[i] ~ dnorm(0.0, tau)
        p[i] = logistic(alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i])
    end
    alpha0 ~ dnorm(0.0, 1.0E-6)
    alpha1 ~ dnorm(0.0, 1.0E-6)
    alpha2 ~ dnorm(0.0, 1.0E-6)
    alpha12 ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau)
end
```
BUGS syntax carries over almost one-to-one to Julia, with a few minor exceptions.
In general, when basic Julia syntax and BUGS syntax conflict, it is necessary to use Julia syntax. 
For example, curly braces are replaced with `begin ... end` blocks, and `for` loops do not require parentheses.
In addition, Julia uses `f(x) = ...` as a shorthand for function definition, so BUGS' link function syntax can be confusing and ambiguous. 
Thus, instead of calling the link function, we call the inverse link function from the RHS.

### Support for Lagacy BUGS Programs
The `@bugs` macro also works with original (R-like) BUGS syntax:

```julia
@bugs("""
model{
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
""", true)
```

By default, `@bugs` will translate R-style variable names like `a.b.c` to `a_b_c`, user can pass `false` as the second argument to disable this. 
We still encourage users to write new programs using the Julia-native syntax, because of better debuggability and perks like syntax highlighting. 

### Using Self-defined Functions and Distributions
Users can register their own functions and distributions with macros. However, note that any functions used with must be _pure_ mathematical functions, i.e. they must be side-effect free.

```julia-repl
julia> # Should be restricted to pure function that do simple operations
@register_primitive function f(x)
    return x + 1
end

julia> JuliaBUGS.f(2)
3
```

users can also `introduce` a function into `JuliaBUGS`, by 

```julia
julia> f(x) = x + 1

julia> @register_primitive(f)

julia> JuliaBUGS.f(1)
2
```

After registering the function or distributions, they can be used just like any other functions or distributions provided by BUGS.

## Compilation

For now, the `compile` function will create a `BUGSModel`, which implements [`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

```julia
compile(model_def::Expr, data, initializations),
```

which takes three arguments: 
- the output of `@bugs`, 
- the data, and
- the initializations of parameters.

```
initializations = Dict(:alpha => 1, :beta => 1)
```

then we can compile the model with the data and initializations,
```julia-repl
julia> model = compile(model_def, data, initializations)
```

`LogDensityProblemsAD.jl` defined some extensions support automatic differentiation packages.
For example, with `ReverseDiff.jl`

```julia
using LogDensityProblemsAD

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))
```
here `ad_model` will also implement all the interface of `LogDensityProblems.jl`. 
`LogDensityProblemsAD.jl` will automatically add interface function `logdensity_and_gradient` to the model, which will return the log density and gradient of the model.  
And `ad_model` can be used in the same way as `model` in the example below.


## Inference

For a differentiable model, we can use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) to perform inference. 
For instance,

```julia
using AdvancedHMC, AbstractMCMC
using ReverseDiff
using LogDensityProblems

D = LogDensityProblems.dimension(model); initial_θ = rand(D)
n_samples, n_adapts = 2000, 1000

metric = DiagEuclideanMetric(D)
hamiltonian = Hamiltonian(metric, model, :ReverseDiff)

initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)

kernel = HMCKernel(Trajectory{MultinomialTS}(integrator, GeneralisedNoUTurn()))
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

samples, stats = sample(hamiltonian, kernel, initial_θ, n_samples, adaptor, n_adapts; progress=true)
```

The variable `samples` contains variable values in the unconstrained space. 
We reloaded the `MCMCChains.Chains` function with package extension to create a named `MCMCChains.Chains` object:
```julia
using MCMCChains

MCMCChains.Chains(samples, model)
```
this will return something similar to
```julia
Chains MCMC chain (2000×27×1 Array{Float64, 3}):

Iterations        = 1:1:2000
Number of chains  = 1
Samples per chain = 2000
parameters        = alpha0, alpha12, alpha1, alpha2, tau, b[16], b[12], b[10], b[14], b[13], b[7], b[6], b[20], b[1], b[4], b[5], b[2], b[18], b[8], b[3], b[9], b[21], b[17], b[15], b[11], b[19], sigma

Summary Statistics
  parameters      mean       std      mcse    ess_bulk    ess_tail      rhat   ess_per_sec 
      Symbol   Float64   Float64   Float64     Float64     Float64   Float64       Missing 

      alpha0   -0.5623    0.2247    0.0084    719.7526   1011.4760    0.9999       missing
     alpha12   -0.8855    0.4874    0.0174    770.5197   1123.7505    0.9998       missing
      alpha1    0.0655    0.3528    0.0125    768.3965   1110.4095    1.0012       missing
      alpha2    1.4002    0.3135    0.0114    765.6003    929.3141    1.0002       missing
         tau    9.7166   10.6698    0.6379    323.1786    362.5801    1.0000       missing
       b[16]   -0.2285    0.4025    0.0098   1819.8930   1164.0437    1.0004       missing
       b[12]    0.1889    0.3268    0.0088   1445.0574   1032.6184    1.0001       missing
       b[10]   -0.3495    0.2713    0.0083   1099.6773    961.3578    1.0009       missing
       b[14]   -0.1925    0.3196    0.0078   1664.2264   1348.2639    0.9999       missing
       b[13]   -0.0959    0.3138    0.0076   1707.8788   1138.8372    1.0001       missing
        b[7]    0.0604    0.2646    0.0072   1383.1284    975.9354    1.0003       missing
      ⋮           ⋮         ⋮         ⋮          ⋮           ⋮          ⋮           ⋮
                                                                             16 rows omitted

Quantiles
  parameters      2.5%     25.0%     50.0%     75.0%     97.5% 
      Symbol   Float64   Float64   Float64   Float64   Float64 

      alpha0   -1.0244   -0.7060   -0.5580   -0.4169   -0.1216
     alpha12   -1.8774   -1.2014   -0.8808   -0.5623    0.0452
      alpha1   -0.6179   -0.1688    0.0700    0.2930    0.7607
      alpha2    0.8000    1.1813    1.3962    1.6003    2.0375
         tau    1.8911    4.1197    6.8022   10.7377   44.1010
       b[16]   -1.1361   -0.4566   -0.1894    0.0348    0.4922
       b[12]   -0.3743   -0.0240    0.1627    0.3804    0.9120
       b[10]   -0.9361   -0.5141   -0.3324   -0.1626    0.1498
       b[14]   -0.8790   -0.3938   -0.1720    0.0134    0.4111
       b[13]   -0.7391   -0.2900   -0.0936    0.1062    0.5369
        b[7]   -0.4485   -0.1096    0.0581    0.2296    0.5896
      ⋮           ⋮         ⋮         ⋮         ⋮         ⋮
                                                 16 rows omitted

```

Which is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

## More Examples
We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/master/src/BUGSExamples/Volume_I)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
