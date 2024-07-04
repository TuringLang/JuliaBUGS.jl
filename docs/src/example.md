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

- [BNF](https://github.com/TuringLang/JuliaBUGS.jl/blob/master/archive/parser_attempts/BNF.txt)

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

`LogDensityProblemsAD.jl` defined some extensions that support automatic differentiation packages.
For example, with `ReverseDiff.jl`

```@example abc
using LogDensityProblemsAD, ReverseDiff

ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))
```

Here `ad_model` will also implement all the interfaces of [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/).
`LogDensityProblemsAD.jl` will automatically add the interface function [`logdensity_and_gradient`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity_and_gradient) to the model, which will return the log density and gradient of the model.  
And `ad_model` can be used in the same way as `model` in the example below.

### Inference

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

```@example abc
using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains # hide
n_samples, n_adapts = 2000, 1000 # hide
D = LogDensityProblems.dimension(model); initial_θ = rand(D) # hide
samples_and_stats = AbstractMCMC.sample(
                        ad_model,
                        NUTS(0.8),
                        n_samples;
                        chain_type = Chains,
                        n_adapts = n_adapts,
                        init_params = initial_θ,
                        discard_initial = n_adapts
                    ) # hide
show(samples_and_stats) # hide
```

```plaintext
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

## Parallel and Distributed Sampling with `AbstractMCMC`

`AbstractMCMC` and `AdvancedHMC` support both parallel and distributed sampling.

### Parallel Sampling

To perform multi-threaded sampling of multiple chains, start the Julia session with the `-t <n_threads>` argument.
The model compilation code remains the same, and we can sample multiple chains in parallel as follows:

```julia
n_chains = 4
samples_and_stats = AbstractMCMC.sample(
    ad_model,
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
    using JuliaBUGS, LogDensityProblems, LogDensityProblemsAD, AbstractMCMC, AdvancedHMC, MCMCChains, ReverseDiff # also other packages one may need

    # Define the functions to use
    # Use `@register_primitive` to register the functions to use in the model

    # Distributed can handle data dependencies in some cases, for more detail, see https://docs.julialang.org/en/v1/manual/distributed-computing/

end

n_chains = nprocs() - 1 # use all the processes except the master process
samples_and_stats = AbstractMCMC.sample(
    ad_model,
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

## More Examples

We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/master/src/BUGSExamples/VOLUME_1)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
