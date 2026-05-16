
# Example: Logistic Regression with Random Effects {#Example:-Logistic-Regression-with-Random-Effects}

We will use the [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) for demonstration. This example concerns the proportion of seeds that germinated on each of 21 plates. Here, we transform the data into a `NamedTuple`:

```julia
data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)
```


where `r[i]` is the number of germinated seeds and `n[i]` is the total number of the seeds on the $i$-th plate. Let $p_i$ be the probability of germination on the $i$-th plate. Then, the model is defined by:

$$\begin{aligned}
b_i &\sim \text{Normal}(0, \tau) \\
\text{logit}(p_i) &= \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
r_i &\sim \text{Binomial}(p_i, n_i)
\end{aligned}$$

where $x_{1i}$ and $x_{2i}$ are the seed type and root extract of the $i$-th plate.   The original BUGS program for the model is:

```S
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


## Modeling Language {#Modeling-Language}

### Writing a Model in BUGS {#Writing-a-Model-in-BUGS}

Language References:
- [MultiBUGS](https://www.multibugs.org/documentation/latest/)
  
- [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)
  

Implementations in C++ and R:
- [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and its [user manual](https://people.stat.sc.edu/hansont/stat740/jags_user_manual.pdf)
  
- [Nimble](https://r-nimble.org/)
  

Language Syntax:
- [BNF](https://github.com/TuringLang/JuliaBUGS.jl/blob/main/archive/parser_attempts/BNF.txt)
  

### Writing a Model in Julia {#Writing-a-Model-in-Julia}

We provide a [macro](https://docs.julialang.org/en/v1/manual/metaprogramming/#man-macros) which allows users to write down model definitions using Julia:

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


BUGS syntax carries over almost one-to-one to Julia, with minor exceptions. Modifications required are minor: curly braces are replaced with `begin ... end` blocks, and `for` loops do not require parentheses. In addition, Julia uses `f(x) = ...` as a shorthand for function definition, so BUGS&#39; link function syntax is disallowed. Instead, user can call the inverse function of the link functions on the RHS expressions.

### Support for Legacy BUGS Programs {#Support-for-Legacy-BUGS-Programs}

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
""", true, true)
```


By default, `@bugs` will translate R-style variable names like `a.b.c` to `a_b_c`, user can pass `false` as the second argument to disable this. User can also pass `true` as the third argument if `model { }` enclosure is not present in the BUGS program. We still encourage users to write new programs using the Julia-native syntax, because of better debuggability and perks like syntax highlighting.

## Basic Workflow {#Basic-Workflow}

### Compilation {#Compilation}

Model definition and data are the two necessary inputs for compilation, with optional initializations. The compile function creates a BUGSModel that implements the [LogDensityProblems.jl](https://github.com/tpapp/LogDensityProblems.jl) interface.

```julia
compile(model_def::Expr, data::NamedTuple)
```


And with initializations:

```julia
compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
```


Using the model definition and data we defined earlier, we can compile the model:

```julia
model = compile(model_def, data)
```


```ansi
BUGSModel (parameters are in transformed (unconstrained) space, with dimension 26):

  Model parameters:
    alpha2
    b[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1]
    tau
    alpha12
    alpha1
    alpha0

  Variable sizes and types:
    b: size = (21,), type = Vector{Float64}
    p: size = (21,), type = Vector{Float64}
    n: size = (21,), type = Vector{Int64}
    alpha2: type = Float64
    sigma: type = Float64
    alpha0: type = Float64
    alpha12: type = Float64
    N: type = Int64
    tau: type = Float64
    alpha1: type = Float64
    r: size = (21,), type = Vector{Int64}
    x1: size = (21,), type = Vector{Int64}
    x2: size = (21,), type = Vector{Int64}
```


Parameter values will be sampled from the prior distributions in the original space.

We can provide initializations:

```julia
initializations = (alpha = 1, beta = 1)
```


```julia
compile(model_def, data, initializations)
```


```ansi
[34m[1mBUGSModel[22m[39m (parameters are in transformed (unconstrained) space, with dimension 26):

[33m[1m  Model parameters:[22m[39m
    [36malpha2[39m
    [36mb[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1][39m
    [36mtau[39m
    [36malpha12[39m
    [36malpha1[39m
    [36malpha0[39m

[33m[1m  Variable sizes and types:[22m[39m
    [36mb[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mp[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mn[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36malpha2[39m: [32mtype = Float64[39m
    [36msigma[39m: [32mtype = Float64[39m
    [36malpha0[39m: [32mtype = Float64[39m
    [36malpha12[39m: [32mtype = Float64[39m
    [36mN[39m: [32mtype = Int64[39m
    [36mtau[39m: [32mtype = Float64[39m
    [36malpha1[39m: [32mtype = Float64[39m
    [36mr[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36mx1[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36mx2[39m: [32msize = (21,), type = Vector{Int64}[39m

```


We can also initialize parameters after compilation:

```julia
initialize!(model, initializations)
```


```ansi
[34m[1mBUGSModel[22m[39m (parameters are in transformed (unconstrained) space, with dimension 26):

[33m[1m  Model parameters:[22m[39m
    [36malpha2[39m
    [36mb[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1][39m
    [36mtau[39m
    [36malpha12[39m
    [36malpha1[39m
    [36malpha0[39m

[33m[1m  Variable sizes and types:[22m[39m
    [36mb[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mp[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mn[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36malpha2[39m: [32mtype = Float64[39m
    [36msigma[39m: [32mtype = Float64[39m
    [36malpha0[39m: [32mtype = Float64[39m
    [36malpha12[39m: [32mtype = Float64[39m
    [36mN[39m: [32mtype = Int64[39m
    [36mtau[39m: [32mtype = Float64[39m
    [36malpha1[39m: [32mtype = Float64[39m
    [36mr[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36mx1[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36mx2[39m: [32msize = (21,), type = Vector{Int64}[39m

```


`initialize!` also accepts a flat vector. In this case, the vector should have the same length as the number of parameters, but values can be in transformed space:

```julia
initialize!(model, rand(26))
```


```ansi
[34m[1mBUGSModel[22m[39m (parameters are in transformed (unconstrained) space, with dimension 26):

[33m[1m  Model parameters:[22m[39m
    [36malpha2[39m
    [36mb[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1][39m
    [36mtau[39m
    [36malpha12[39m
    [36malpha1[39m
    [36malpha0[39m

[33m[1m  Variable sizes and types:[22m[39m
    [36mb[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mp[39m: [32msize = (21,), type = Vector{Float64}[39m
    [36mn[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36malpha2[39m: [32mtype = Float64[39m
    [36msigma[39m: [32mtype = Float64[39m
    [36malpha0[39m: [32mtype = Float64[39m
    [36malpha12[39m: [32mtype = Float64[39m
    [36mN[39m: [32mtype = Int64[39m
    [36mtau[39m: [32mtype = Float64[39m
    [36mr[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36malpha1[39m: [32mtype = Float64[39m
    [36mx1[39m: [32msize = (21,), type = Vector{Int64}[39m
    [36mx2[39m: [32msize = (21,), type = Vector{Int64}[39m

```


### Inference {#Inference}

For gradient-based inference, compile your model with an AD backend using the `adtype` parameter (see [Automatic Differentiation](inference/ad.md) for details). We use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl):

```julia
# Compile with gradient support
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model); initial_θ = rand(D)

samples_and_stats = AbstractMCMC.sample(
                        model,
                        NUTS(0.8),
                        n_samples;
                        chain_type = Chains,
                        n_adapts = n_adapts,
                        init_params = initial_θ,
                        discard_initial = n_adapts,
                        progress = false
                    )
describe(samples_and_stats)
```


```ansi
[ Info: Found initial step size 0.2
Chains MCMC chain (2000×40×1 Array{Real, 3}):

Iterations        = 1001:1:3000
Number of chains  = 1
Samples per chain = 2000
parameters        = tau, alpha12, alpha2, alpha1, alpha0, b[21], b[20], b[19], b[18], b[17], b[16], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8], b[7], b[6], b[5], b[4], b[3], b[2], b[1], sigma
internals         = lp, n_steps, is_accept, acceptance_rate, log_density, hamiltonian_energy, hamiltonian_energy_error, max_hamiltonian_energy_error, tree_depth, numerical_error, step_size, nom_step_size, is_adapt

Summary Statistics

  parameters      mean        std      mcse    ess_bulk    ess_tail      rhat  ⋯
      Symbol   Float64    Float64   Float64        Real     Float64   Float64  ⋯

         tau   52.4323   130.9233   14.9760    116.7576    108.1046    1.0031  ⋯
     alpha12   -0.8026     0.4389    0.0153    871.3180    842.7369    1.0004  ⋯
      alpha2    1.3472     0.2652    0.0092    838.6467    871.3383    0.9999  ⋯
      alpha1    0.0636     0.3226    0.0116    799.1818   1039.1874    1.0003  ⋯
      alpha0   -0.5478     0.1926    0.0068    841.7903    833.8126    1.0006  ⋯
       b[21]   -0.0475     0.2960    0.0071   2005.3054    853.2614    1.0025  ⋯
       b[20]    0.2180     0.2779    0.0113    639.7455   1023.8699    1.0016  ⋯
       b[19]   -0.0088     0.2541    0.0058   2109.5139    884.9403    1.0011  ⋯
       b[18]    0.0476     0.2523    0.0061   1889.8089   1146.3316    0.9999  ⋯
       b[17]   -0.2081     0.3020    0.0124    724.3134    878.5903    0.9997  ⋯
       b[16]   -0.1399     0.3361    0.0109   1296.8914    816.7973    1.0072  ⋯
       b[15]    0.2377     0.2777    0.0140    405.6083    700.3442    0.9995  ⋯
       b[14]   -0.1307     0.2452    0.0075   1116.9836   1266.2988    0.9998  ⋯
       b[13]   -0.0607     0.2617    0.0060   2012.6982   1145.9802    1.0009  ⋯
       b[12]    0.1252     0.2783    0.0092   1293.8689    843.2045    1.0003  ⋯
           ⋮         ⋮          ⋮         ⋮           ⋮           ⋮         ⋮  ⋱

                                                    1 column and 12 rows omitted

Quantiles

  parameters      2.5%     25.0%     50.0%     75.0%      97.5%
      Symbol   Float64   Float64   Float64   Float64    Float64

         tau    2.5672    6.9867   13.6874   30.1699   459.4839
     alpha12   -1.6581   -1.0615   -0.8114   -0.5251     0.0426
      alpha2    0.8420    1.1733    1.3483    1.5076     1.9049
      alpha1   -0.5833   -0.1421    0.0794    0.2698     0.6946
      alpha0   -0.9382   -0.6661   -0.5447   -0.4301    -0.1441
       b[21]   -0.7495   -0.1925   -0.0273    0.1171     0.5211
       b[20]   -0.2218    0.0207    0.1765    0.3758     0.8778
       b[19]   -0.5086   -0.1450   -0.0115    0.1227     0.5277
       b[18]   -0.4430   -0.0940    0.0343    0.1859     0.5972
       b[17]   -0.9319   -0.3732   -0.1505   -0.0004     0.2591
       b[16]   -0.9420   -0.2970   -0.0820    0.0577     0.4216
       b[15]   -0.1932    0.0476    0.2004    0.3992     0.9033
       b[14]   -0.6995   -0.2739   -0.0980    0.0208     0.3147
       b[13]   -0.6337   -0.1939   -0.0442    0.0772     0.4711
       b[12]   -0.3643   -0.0468    0.0874    0.2720     0.7792
           ⋮         ⋮         ⋮         ⋮         ⋮          ⋮

                                                  12 rows omitted
```


This is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

## Next Steps {#Next-Steps}
- [Automatic Differentiation](inference/ad.md) - AD backends and configuration
  
- [Evaluation Modes](inference/evaluation_modes.md) - Different log density computation modes
  
- [Auto-Marginalization](inference/auto_marginalization.md) - Gradient-based inference with discrete variables
  
- [Parallel Sampling](inference/parallel.md) - Multi-threaded and distributed sampling
  

## More Examples {#More-Examples}

We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/main/JuliaBUGS/src/BUGSExamples/Volume_1)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
