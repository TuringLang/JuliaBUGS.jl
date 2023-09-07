# JuliaBUGS.jl

A modern implementation of the BUGS probabilistic programming language in Julia. 

## Caution!

JuliaBUGS is still in beta and may not be ready for serious use.

## Installation
To install the package, run the following command in the Julia REPL:
```julia
]  # Enter Pkg mode by pressing `] `
(@v1.9) pkg> add JuliaBUGS
```
Then run the following command to use the package:
```julia
using JuliaBUGS
```

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
Let $p_i$ be the probability of germination on the $i$-th plate. Then, the model is defined by:

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
model_def = @bugs begin
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
BUGS syntax carries over almost one-to-one to Julia, with minor exceptions.
In general, when basic Julia syntax and BUGS syntax conflict, it is necessary to use Julia syntax. 
For example, curly braces are replaced with `begin ... end` blocks, and `for` loops do not require parentheses.
In addition, Julia uses `f(x) = ...` as a shorthand for function definition, so BUGS' link function syntax can be confusing and ambiguous. 
Thus, instead of calling the link function, we call the inverse link function from the RHS.

### Support for Legacy BUGS Programs
The `@bugs` macro also works with original (R-like) BUGS syntax:

```julia
model_def = @bugs("""
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
Users can register their own functions and distributions with macros. However, note that any functions used must be _pure_ mathematical functions, i.e., side-effect free.

```julia
julia> # Should be restricted to pure functions that do simple operations
@register_primitive function f(x)
    return x + 1
end

julia> JuliaBUGS.f(2)
3
```

Users can also `introduce` a function into `JuliaBUGS`, by 

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

The function `compile` takes three arguments: 
- the output of `@bugs`, 
- the data, and
- the initializations of parameters.

```julia
initializations = Dict(:alpha => 1, :beta => 1)
```

then we can compile the model with the data and initializations,
```julia
model = compile(model_def, data, initializations)
```

`LogDensityProblemsAD.jl` defined some extensions that support automatic differentiation packages.
For example, with `ReverseDiff.jl`

```julia
using LogDensityProblemsAD, ReverseDiff

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))
```
Here `ad_model` will also implement all the interfaces of `LogDensityProblems.jl`. 
`LogDensityProblemsAD.jl` will automatically add the interface function `logdensity_and_gradient` to the model, which will return the log density and gradient of the model.  
And `ad_model` can be used in the same way as `model` in the example below.


## Inference

For a differentiable model, we can use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) to perform inference. 
For instance,

```julia
using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model); initial_θ = rand(D)

samples_and_stats = AbstractMCMC.sample(
                        ad_model,
                        NUTS(0.8),
                        n_samples;
                        chain_type = Chains,
                        n_adapts = n_adapts,
                        init_params = initial_θ,
                        discard_initial = n_adapts
                    )
```

This will return the MCMC Chain,

```julia
Chains MCMC chain (2000×40×1 Array{Real, 3}):

Iterations        = 1001:1:3000
Number of chains  = 1
Samples per chain = 2000
parameters        = alpha0, alpha12, alpha1, alpha2, tau, b[16], b[12], b[10], b[14], b[13], b[7], b[6], b[20], b[1], b[4], b[5], b[2], b[18], b[8], b[3], b[9], b[21], b[17], b[15], b[11], b[19], sigma
internals         = lp, n_steps, is_accept, acceptance_rate, log_density, hamiltonian_energy, hamiltonian_energy_error, max_hamiltonian_energy_error, tree_depth, numerical_error, step_size, nom_step_size, is_adapt

Summary Statistics
  parameters      mean       std      mcse    ess_bulk    ess_tail      rhat   ess_per_sec 
      Symbol   Float64   Float64   Float64        Real     Float64   Float64       Missing 

      alpha0   -0.5642    0.2320    0.0084    766.9305   1022.5211    1.0021       missing
     alpha12   -0.8489    0.5247    0.0170    946.0418   1044.1109    1.0002       missing
      alpha1    0.0587    0.3715    0.0119    966.4367   1233.2257    1.0007       missing
      alpha2    1.3852    0.3410    0.0127    712.2978    974.1566    1.0002       missing
         tau    1.8880    0.7705    0.0447    348.9331    338.3655    1.0030       missing
       b[16]   -0.2445    0.4459    0.0132   1528.0578    843.8225    1.0003       missing
       b[12]    0.2050    0.3602    0.0086   1868.6126   1202.1363    0.9996       missing
       b[10]   -0.3500    0.2893    0.0090   1047.3119   1245.9358    1.0008       missing
      ⋮           ⋮         ⋮         ⋮          ⋮           ⋮          ⋮           ⋮
                                                                             19 rows omitted

Quantiles
  parameters      2.5%     25.0%     50.0%     75.0%     97.5% 
      Symbol   Float64   Float64   Float64   Float64   Float64 

      alpha0   -1.0143   -0.7143   -0.5590   -0.4100   -0.1185
     alpha12   -1.9063   -1.1812   -0.8296   -0.5153    0.1521
      alpha1   -0.6550   -0.1822    0.0512    0.2885    0.8180
      alpha2    0.7214    1.1663    1.3782    1.5998    2.0986
         tau    0.5461    1.3941    1.8353    2.3115    3.6225
       b[16]   -1.2359   -0.4836   -0.1909    0.0345    0.5070
       b[12]   -0.4493   -0.0370    0.1910    0.4375    0.9828
       b[10]   -0.9570   -0.5264   -0.3331   -0.1514    0.1613
      ⋮           ⋮         ⋮         ⋮         ⋮         ⋮
                                                 19 rows omitted

```

This is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

## More Examples
We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/master/src/BUGSExamples/Volume_I)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
