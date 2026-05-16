
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

         tau   37.0743   78.7449    7.8871     63.4304    100.2433    1.0462   ⋯
     alpha12   -0.8152    0.4339    0.0161    719.8699    816.8319    1.0064   ⋯
      alpha2    1.3446    0.2584    0.0083    951.9279    858.5653    1.0122   ⋯
      alpha1    0.0750    0.3019    0.0122    618.2287    800.8169    1.0057   ⋯
      alpha0   -0.5473    0.1845    0.0064    837.5602    807.6041    1.0113   ⋯
       b[21]   -0.0359    0.2763    0.0058   2387.3599   1073.3777    1.0134   ⋯
       b[20]    0.2276    0.2767    0.0171    292.8864    943.3839    1.0114   ⋯
       b[19]   -0.0068    0.2570    0.0063   1779.9338    760.2805    1.0119   ⋯
       b[18]    0.0502    0.2543    0.0070   1405.3244   1102.7914    1.0048   ⋯
       b[17]   -0.2188    0.3118    0.0129    703.9186    753.5959    1.0081   ⋯
       b[16]   -0.1412    0.3302    0.0146    670.9153    530.6116    1.0109   ⋯
       b[15]    0.2417    0.2753    0.0146    389.7531   1177.5245    1.0143   ⋯
       b[14]   -0.1479    0.2615    0.0087    902.6903   1027.7728    1.0061   ⋯
       b[13]   -0.0689    0.2527    0.0058   1918.5185   1038.6232    1.0115   ⋯
       b[12]    0.1264    0.2815    0.0092   1295.4950    665.3761    1.0162   ⋯
           ⋮         ⋮         ⋮         ⋮           ⋮           ⋮         ⋮   ⋱

                                                    1 column and 12 rows omitted

Quantiles

  parameters      2.5%     25.0%     50.0%     75.0%      97.5%
      Symbol   Float64   Float64   Float64   Float64    Float64

         tau    2.7648    7.0587   12.6442   28.3934   279.2973
     alpha12   -1.7097   -1.0913   -0.8194   -0.5255     0.0254
      alpha2    0.8171    1.1805    1.3441    1.5063     1.8621
      alpha1   -0.5741   -0.1162    0.0861    0.2804     0.6503
      alpha0   -0.9235   -0.6634   -0.5478   -0.4308    -0.1767
       b[21]   -0.6082   -0.1817   -0.0292    0.1195     0.5136
       b[20]   -0.2520    0.0292    0.1892    0.3956     0.8684
       b[19]   -0.5198   -0.1568   -0.0065    0.1256     0.5629
       b[18]   -0.4236   -0.0991    0.0365    0.1890     0.5978
       b[17]   -0.9332   -0.3831   -0.1744   -0.0069     0.2776
       b[16]   -0.9719   -0.2890   -0.0864    0.0526     0.4057
       b[15]   -0.2069    0.0387    0.2060    0.4088     0.8451
       b[14]   -0.7307   -0.2915   -0.1109    0.0113     0.2978
       b[13]   -0.6106   -0.2116   -0.0472    0.0800     0.4237
       b[12]   -0.3555   -0.0462    0.0842    0.2716     0.7839
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
