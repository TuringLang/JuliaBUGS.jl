# JuliaBUGS.jl

A modern implementation of the BUGS language in Julia. 

## Caution!

This is still a work in progress and may not be ready for serious use.

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
r_i &\sim \text{Binomial}(p_i, n_i) \\
\text{logit}(p_i) &\sim \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
b_i &\sim \text{Normal}(0, \tau)
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

BUGS language syntax: [ANF definition](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/archive/parser_attempts/BNF.txt)

Language References:  
 - [MultiBUGS](https://www.multibugs.org/documentation/latest/)
 - [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)

Implementations in C++ and R:
- [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and its [user manual](https://people.stat.sc.edu/hansont/stat740/jags_user_manual.pdf)
- [Nimble](https://r-nimble.org/)

### Writing Model in Julia
We provide a macro solution which allows users to write down model definitions using Julia:

```julia
@bugs begin
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

For now, the `compile` function will create a `BUGSLogDensityProblem`, which is fully conform to [`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl).

```julia
compile(model_def::Expr, data::Dict, initializations::Dict),
```

which takes three arguments: 
- the first argument is the output of `@bugsast` or `bugsmodel`, 
- the second argument is the data 
- the third argument is the initializations of the parameters, in the case of `pumps` model, it is

```
initializaitons = Dict(:alpha => 1, :beta => 1)
```

then we can compile the model with the data and initializations,
```julia-repo
julia> p = compile(model_def, data, initializations);

```

## Inference

For a differentiable model, we can use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) to perform inference. 
We can start with the setup exactly the same as the example on the `AdvancedHMC.jl` page:

```julia
using AdvancedHMC
using ReverseDiff
using LogDensityProblems

D = LogDensityProblems.dimension(p)
n_samples, n_adapts = 2000, 1000

metric = DiagEuclideanMetric(D)
hamiltonian = Hamiltonian(metric, p, :ReverseDiff)

initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
integrator = Leapfrog(initial_ϵ)
proposal = NUTS{MultinomialTS, GeneralisedNoUTurn}(integrator)
adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

samples, stats = sample(hamiltonian, proposal, initial_θ, n_samples, adaptor, n_adapts; drop_warmup=true, progress=true);
```

The variable `samples` contains variable values in the unconstrained space, we can use the function `JuliaBUGS.transform_samples` to get a dictionary mapping variable names to their sample values.

```julia-repo
julia> alpha_0_samples = [JuliaBUGS.transform_samples(p, sample)[JuliaBUGS.Var(:alpha0)] for sample in samples]; 

julia> mean(alpha_0_samples), std(alpha_0_samples) # Reference result: mean -0.5499, variance 0.1965
(-0.5432579688203603, 0.23682544392999907)
```

One can verify the inference result is coherent with BUGS' result for [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html). 

## More Examples
We have transcribed all the examples from the first volume of the BUGS Examples ([origianl](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/master/src/BUGSExamples/Volume_I)). All the programs and data are included, and they can be compiled in a similar way as we have demonstrated before.

