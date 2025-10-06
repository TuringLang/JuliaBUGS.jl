# Example: Logistic Regression with Random Effects

```@setup abc
using JuliaBUGS

data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)

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

initializations = (alpha = 1, beta = 1)
```

We will use the [Seeds](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html) for demonstration.
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

```math
\begin{aligned}
b_i &\sim \text{Normal}(0, \tau) \\
\text{logit}(p_i) &= \alpha_0 + \alpha_1 x_{1 i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_{i} \\
r_i &\sim \text{Binomial}(p_i, n_i)
\end{aligned}
```

where $x_{1i}$ and $x_{2i}$ are the seed type and root extract of the $i$-th plate.  
The original BUGS program for the model is:

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

## Modeling Language

### Writing a Model in BUGS

Language References:

- [MultiBUGS](https://www.multibugs.org/documentation/latest/)
- [OpenBUGS](https://chjackson.github.io/openbugsdoc/Manuals/ModelSpecification.html)

Implementations in C++ and R:

- [JAGS](https://sourceforge.net/p/mcmc-jags/code-0/ci/default/tree/) and its [user manual](https://people.stat.sc.edu/hansont/stat740/jags_user_manual.pdf)
- [Nimble](https://r-nimble.org/)

Language Syntax:

- [BNF](https://github.com/TuringLang/JuliaBUGS.jl/blob/main/archive/parser_attempts/BNF.txt)

### Writing a Model in Julia

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

BUGS syntax carries over almost one-to-one to Julia, with minor exceptions.
Modifications required are minor: curly braces are replaced with `begin ... end` blocks, and `for` loops do not require parentheses.
In addition, Julia uses `f(x) = ...` as a shorthand for function definition, so BUGS' link function syntax is disallowed.
Instead, user can call the inverse function of the link functions on the RHS expressions.

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
""", true, true)
```

By default, `@bugs` will translate R-style variable names like `a.b.c` to `a_b_c`, user can pass `false` as the second argument to disable this.
User can also pass `true` as the third argument if `model { }` enclosure is not present in the BUGS program.
We still encourage users to write new programs using the Julia-native syntax, because of better debuggability and perks like syntax highlighting.

## Basic Workflow

### Compilation

Model definition and data are the two necessary inputs for compilation, with optional initializations. The compile function creates a BUGSModel that implements the [LogDensityProblems.jl](https://github.com/tpapp/LogDensityProblems.jl) interface.

```julia
compile(model_def::Expr, data::NamedTuple)
```

And with initializations:

```julia
compile(model_def::Expr, data::NamedTuple, initializations::NamedTuple)
```

Using the model definition and data we defined earlier, we can compile the model:

```@example abc
model = compile(model_def, data)
show(model) # hide
```

Parameter values will be sampled from the prior distributions in the original space.

We can provide initializations:

```julia
initializations = (alpha = 1, beta = 1)
```

```@example abc
compile(model_def, data, initializations)
```

We can also initialize parameters after compilation:

```@example abc
initialize!(model, initializations)
```

`initialize!` also accepts a flat vector. In this case, the vector should have the same length as the number of parameters, but values can be in transformed space:

```@example abc
initialize!(model, rand(26))
```

### Automatic Differentiation

JuliaBUGS integrates with automatic differentiation (AD) through [DifferentiationInterface.jl](https://github.com/JuliaDiff/DifferentiationInterface.jl), enabling gradient-based inference methods like Hamiltonian Monte Carlo (HMC) and No-U-Turn Sampler (NUTS).

#### Specifying an AD Backend

To compile a model with gradient support, pass the `adtype` parameter to `compile`:

```julia
# Using explicit ADType from ADTypes.jl
using ADTypes
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

# Using convenient symbol shortcuts
model = compile(model_def, data; adtype=:ReverseDiff)  # Equivalent to above
```

Available AD backends include:
- `:ReverseDiff` - ReverseDiff with tape compilation (recommended for most models)
- `:ForwardDiff` - ForwardDiff (efficient for models with few parameters)
- `:Zygote` - Zygote (source-to-source AD)
- `:Enzyme` - Enzyme (experimental, high-performance)

For fine-grained control, use explicit `ADTypes` constructors:

```julia
# ReverseDiff without compilation
model = compile(model_def, data; adtype=AutoReverseDiff(compile=false))
```

The compiled model with gradient support implements the [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/) interface, including [`logdensity_and_gradient`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity_and_gradient), which returns both the log density and its gradient.

### Inference

For gradient-based inference, we use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) with models compiled with an `adtype`:

```julia
using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains, ReverseDiff

# Compile with gradient support
model = compile(model_def, data; adtype=:ReverseDiff)

n_samples, n_adapts = 2000, 1000

D = LogDensityProblems.dimension(model); initial_θ = rand(D)

samples_and_stats = AbstractMCMC.sample(
                        model,
                        NUTS(0.8),
                        n_samples;
                        chain_type = Chains,
                        n_adapts = n_adapts,
                        init_params = initial_θ,
                        discard_initial = n_adapts
                    )
describe(samples_and_stats)
```

This will return the MCMC Chain,

```plaintext
Chains MCMC chain (2000×40×1 Array{Real, 3}):

Iterations        = 1001:1:3000
Number of chains  = 1
Samples per chain = 2000
parameters        = tau, alpha12, alpha2, alpha1, alpha0, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16], b[17], b[18], b[19], b[20], b[21], sigma
internals         = lp, n_steps, is_accept, acceptance_rate, log_density, hamiltonian_energy, hamiltonian_energy_error, max_hamiltonian_energy_error, tree_depth, numerical_error, step_size, nom_step_size, is_adapt

Summary Statistics
  parameters      mean        std      mcse    ess_bulk    ess_tail      rhat   ess_per_sec 
      Symbol   Float64    Float64   Float64        Real     Float64   Float64       Missing

         tau   73.1490   193.8441   43.2582     56.3430     20.6688    1.0155       missing
     alpha12   -0.8052     0.4392    0.0158    761.2180   1049.1664    1.0020       missing
      alpha2    1.3428     0.2813    0.0140    422.8810   1013.2570    1.0061       missing
      alpha1    0.0845     0.3126    0.0113    773.2202    981.8487    1.0051       missing
      alpha0   -0.5480     0.1944    0.0087    537.6212   1156.2083    1.0014       missing
        b[1]   -0.1905     0.2540    0.0129    374.3372    971.7526    1.0034       missing
        b[2]    0.0161     0.2178    0.0056   1505.6353   1002.8787    1.0001       missing
        b[3]   -0.1986     0.2375    0.0128    367.6766   1287.8215    1.0015       missing
        b[4]    0.2792     0.2498    0.0163    201.1558   1168.7538    1.0068       missing
        b[5]    0.1170     0.2397    0.0092    659.5422   1484.8584    1.0016       missing
        b[6]    0.0667     0.2821    0.0074   1745.5567    902.1014    1.0067       missing
        b[7]    0.0597     0.2218    0.0055   1589.5590   1145.6017    1.0065       missing
        b[8]    0.1769     0.2316    0.0102    554.5974   1318.8089    1.0001       missing
        b[9]   -0.1257     0.2233    0.0073    930.0346   1186.4283    1.0031       missing
       b[10]   -0.2513     0.2392    0.0159    213.6323   1142.4487    1.0096       missing
       b[11]    0.0768     0.2783    0.0081   1376.5999   1218.1537    1.0009       missing
       b[12]    0.1171     0.2768    0.0079   1354.9409   1130.8217    1.0052       missing
       b[13]   -0.0688     0.2433    0.0055   1895.0387   1527.7066    1.0010       missing
       b[14]   -0.1363     0.2558    0.0075   1276.0992   1208.8587    1.0001       missing
       b[15]    0.2334     0.2757    0.0135    439.2241    837.3396    1.0036       missing
       b[16]   -0.1212     0.3024    0.0106   1093.4416    914.9457    0.9997       missing
       b[17]   -0.2120     0.3142    0.0166    360.6420    702.4098    1.0009       missing
       b[18]    0.0346     0.2282    0.0056   1665.0325   1281.7179    1.0011       missing
       b[19]   -0.0244     0.2400    0.0052   2186.7638   1179.6971    1.0132       missing
       b[20]    0.2108     0.2421    0.0131    349.7657   1263.5781    1.0016       missing
       b[21]   -0.0509     0.2813    0.0061   2200.5614    916.6256    0.9998       missing
       sigma    0.2797     0.1362    0.0168     56.3430     21.4971    1.0123       missing

Quantiles
  parameters      2.5%     25.0%     50.0%     75.0%      97.5% 
      Symbol   Float64   Float64   Float64   Float64    Float64

         tau    3.1280    7.4608   13.0338   28.2289   929.6520
     alpha12   -1.6645   -1.0887   -0.7952   -0.5635     0.1162
      alpha2    0.8398    1.1494    1.3233    1.5337     1.9177
      alpha1   -0.5796   -0.1059    0.1042    0.2883     0.6702
      alpha0   -0.9340   -0.6751   -0.5463   -0.4086    -0.1752
        b[1]   -0.7430   -0.3415   -0.1566   -0.0074     0.2535
        b[2]   -0.4261   -0.1083    0.0192    0.1420     0.4810
        b[3]   -0.7394   -0.3377   -0.1687   -0.0242     0.2041
        b[4]   -0.1108    0.0873    0.2409    0.4375     0.8267
        b[5]   -0.3141   -0.0458    0.0900    0.2563     0.6489
        b[6]   -0.4679   -0.0896    0.0291    0.2202     0.7060
        b[7]   -0.3861   -0.0685    0.0534    0.1847     0.5207
        b[8]   -0.2326    0.0221    0.1505    0.3162     0.6861
        b[9]   -0.6007   -0.2482   -0.0984    0.0057     0.2771
       b[10]   -0.7936   -0.4108   -0.2255   -0.0617     0.1290
       b[11]   -0.4381   -0.0796    0.0353    0.2178     0.7232
       b[12]   -0.3806   -0.0451    0.0750    0.2671     0.7625
       b[13]   -0.5841   -0.2135   -0.0443    0.0652     0.4055
       b[14]   -0.6854   -0.2872   -0.1015    0.0147     0.3476
       b[15]   -0.2054    0.0257    0.1898    0.4004     0.8660
       b[16]   -0.8173   -0.2829   -0.0804    0.0532     0.4094
       b[17]   -0.9071   -0.3911   -0.1595    0.0099     0.2864
       b[18]   -0.4526   -0.0919    0.0140    0.1686     0.4985
       b[19]   -0.5055   -0.1547   -0.0091    0.1134     0.4528
       b[20]   -0.2120    0.0318    0.1788    0.3673     0.7416
       b[21]   -0.6482   -0.2044   -0.0263    0.1051     0.5246
       sigma    0.0328    0.1882    0.2770    0.3661     0.5654
```

This is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

## Parallel and Distributed Sampling with `AbstractMCMC`

`AbstractMCMC` and `AdvancedHMC` support both parallel and distributed sampling.

### Parallel Sampling

To perform multi-threaded sampling of multiple chains, start the Julia session with the `-t <n_threads>` argument.
The model compilation code remains the same, and we can sample multiple chains in parallel as follows:

```julia
n_chains = 4
samples_and_stats = AbstractMCMC.sample(
    model,
    AdvancedHMC.NUTS(0.65),
    AbstractMCMC.MCMCThreads(),
    n_samples,
    n_chains;
    chain_type = Chains,
    n_adapts = n_adapts,
    init_params = [initial_θ for _ = 1:n_chains],
    discard_initial = n_adapts,
)
```

In this case, we pass two additional arguments to `AbstractMCMC.sample`:

- `AbstractMCMC.MCMCThreads()`: the sampler type, and
- `n_chains`: the number of chains to sample.

### Distributed Sampling

To perform distributed sampling of multiple chains, start the Julia session with the `-p <n_processes>` argument.

In distributed mode, ensure that all functions and modules are available on all processes.
Use `@everywhere` to make the functions and modules available on all processes.

For example:

```julia
@everywhere begin
    using JuliaBUGS, LogDensityProblems, AbstractMCMC, AdvancedHMC, MCMCChains, ADTypes, ReverseDiff

    # Define the functions to use
    # Use `@bugs_primitive` to register the functions to use in the model

    # Distributed can handle data dependencies in some cases, for more detail, see https://docs.julialang.org/en/v1/manual/distributed-computing/

end

n_chains = nprocs() - 1 # use all the processes except the parent process
samples_and_stats = AbstractMCMC.sample(
    model,
    AdvancedHMC.NUTS(0.65),
    AbstractMCMC.MCMCDistributed(),
    n_samples,
    n_chains;
    chain_type = Chains,
    n_adapts = n_adapts,
    init_params = [initial_θ for _ = 1:n_chains], # each chain has its own initial parameters
    discard_initial = n_adapts,
    progress = false, # Base.TTY creating problems in distributed setting
)
```

In this case, we pass two additional arguments to `AbstractMCMC.sample`:

- `AbstractMCMC.MCMCDistributed()`: the sampler type, and
- `n_chains`: the number of chains to sample.
  Note that the `init_params` argument is now a vector of initial parameters for each chain.
  Sometimes the progress logger can cause problems in distributed setting, so we can disable it by setting `progress = false`.

## Choosing an Automatic Differentiation Backend

JuliaBUGS integrates with multiple automatic differentiation (AD) backends through [DifferentiationInterface.jl](https://github.com/JuliaDiff/DifferentiationInterface.jl), providing flexibility to choose the most suitable backend for your model.

### Available Backends

The following AD backends are supported via convenient symbol shortcuts:

- **`:ReverseDiff`** (recommended) — Tape-based reverse-mode AD, highly efficient for models with many parameters. Uses compilation by default for optimal performance.
- **`:ForwardDiff`** — Forward-mode AD, efficient for models with few parameters (typically < 20).
- **`:Zygote`** — Source-to-source reverse-mode AD, general-purpose but may be slower than ReverseDiff for many models.
- **`:Enzyme`** — Experimental high-performance AD backend with LLVM-level transformations.
- **`:Mooncake`** — High-performance reverse-mode AD with advanced optimizations.

### Usage Examples

#### Basic Usage with Symbol Shortcuts

The simplest way to specify an AD backend is using symbol shortcuts:

```julia
# ReverseDiff with tape compilation (recommended for most models)
model = compile(model_def, data; adtype=:ReverseDiff)

# ForwardDiff (good for small models with few parameters)
model = compile(model_def, data; adtype=:ForwardDiff)

# Zygote (source-to-source AD)
model = compile(model_def, data; adtype=:Zygote)
```

#### Advanced Configuration

For fine-grained control, use explicit `ADTypes` constructors:

```julia
using ADTypes

# ReverseDiff without tape compilation
model = compile(model_def, data; adtype=AutoReverseDiff(compile=false))

# ReverseDiff with compilation (equivalent to :ReverseDiff)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))
```

### Performance Considerations

- **ReverseDiff with compilation** (`:ReverseDiff`) is recommended for most models, especially those with many parameters. Compilation adds a one-time overhead but significantly speeds up subsequent gradient evaluations.

- **ForwardDiff** (`:ForwardDiff`) is often faster for models with few parameters (< 20), as it avoids tape construction overhead.

- **Tape compilation trade-off**: While `AutoReverseDiff(compile=true)` has higher initial compilation time, it provides faster gradient evaluations during sampling. For quick prototyping or models that will only be sampled a few times, `AutoReverseDiff(compile=false)` may be preferable.

!!! warning "Compiled tapes and control flow"
    Compiled ReverseDiff tapes cannot handle value-dependent control flow (e.g., `if x[1] > 0`). If your model has such control flow, use `AutoReverseDiff(compile=false)` or a different backend like `:ForwardDiff` or `:Mooncake`. See the [ReverseDiff documentation](https://juliadiff.org/ReverseDiff.jl/stable/api/#The-AbstractTape-API) for details.

### Compatibility

All models compiled with an `adtype` implement the full [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/) interface, making them compatible with:

- [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) — NUTS and HMC samplers
- Any other sampler that works with the LogDensityProblems interface

The gradient computation is prepared during model compilation for optimal performance during sampling.

## More Examples

We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/main/JuliaBUGS/src/BUGSExamples/Volume_1)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
