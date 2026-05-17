
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

```r
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

  parameters      mean       std      mcse    ess_bulk    ess_tail      rhat   ⋯
      Symbol   Float64   Float64   Float64        Real     Float64   Float64   ⋯

         tau   38.8589   83.0657    8.3472    111.7573    131.0218    1.0037   ⋯
     alpha12   -0.8383    0.4299    0.0144    868.2600   1178.7602    1.0003   ⋯
      alpha2    1.3524    0.2691    0.0091    877.7515   1012.1423    1.0029   ⋯
      alpha1    0.0856    0.3090    0.0109    828.5546   1089.8535    1.0005   ⋯
      alpha0   -0.5496    0.1815    0.0062    870.2889   1148.3533    1.0000   ⋯
       b[21]   -0.0379    0.2925    0.0063   2282.7062   1002.8293    0.9996   ⋯
       b[20]    0.2272    0.2601    0.0112    526.8728   1048.0428    1.0003   ⋯
       b[19]   -0.0059    0.2491    0.0056   2012.2913   1188.9284    1.0007   ⋯
       b[18]    0.0464    0.2350    0.0053   2057.3036   1278.4208    0.9998   ⋯
       b[17]   -0.2004    0.2950    0.0138    522.1247   1054.8707    1.0051   ⋯
       b[16]   -0.1395    0.3080    0.0090   1645.0835    880.0808    1.0035   ⋯
       b[15]    0.2244    0.2747    0.0117    610.5001   1250.8011    1.0000   ⋯
       b[14]   -0.1480    0.2661    0.0082   1311.9190   1146.2080    1.0007   ⋯
       b[13]   -0.0763    0.2588    0.0065   1660.7133   1076.0293    1.0009   ⋯
       b[12]    0.1144    0.2865    0.0091   1254.1952    859.2783    0.9998   ⋯
           ⋮         ⋮         ⋮         ⋮           ⋮           ⋮         ⋮   ⋱

                                                    1 column and 12 rows omitted

Quantiles

  parameters      2.5%     25.0%     50.0%     75.0%      97.5%
      Symbol   Float64   Float64   Float64   Float64    Float64

         tau    2.6493    7.4028   13.3802   28.7085   289.6097
     alpha12   -1.6999   -1.1004   -0.8289   -0.5618     0.0064
      alpha2    0.8428    1.1807    1.3483    1.5095     1.9338
      alpha1   -0.5449   -0.1028    0.0971    0.2857     0.6736
      alpha0   -0.9077   -0.6640   -0.5534   -0.4293    -0.1872
       b[21]   -0.6763   -0.1907   -0.0224    0.1228     0.5367
       b[20]   -0.1854    0.0453    0.1853    0.3786     0.8423
       b[19]   -0.5319   -0.1310   -0.0042    0.1272     0.5159
       b[18]   -0.4305   -0.0884    0.0275    0.1750     0.5523
       b[17]   -0.8830   -0.3569   -0.1469   -0.0036     0.2610
       b[16]   -0.8947   -0.2733   -0.0928    0.0417     0.3995
       b[15]   -0.2261    0.0301    0.1834    0.3798     0.8547
       b[14]   -0.7572   -0.3001   -0.1098    0.0260     0.3257
       b[13]   -0.6282   -0.2225   -0.0577    0.0612     0.4475
       b[12]   -0.3831   -0.0591    0.0791    0.2634     0.7786
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
