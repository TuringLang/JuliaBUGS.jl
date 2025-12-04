# Example: Logistic Regression with Random Effects

```@setup abc
using JuliaBUGS
using AdvancedHMC, AbstractMCMC, LogDensityProblems, MCMCChains, ADTypes, ReverseDiff

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
# Compile with gradient support using ADTypes from ADTypes.jl
using ADTypes
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))
```

Alternatively, if you already have a compiled `BUGSModel`, you can wrap it with `BUGSModelWithGradient` without recompiling:

```julia
base_model = compile(model_def, data)
model = BUGSModelWithGradient(base_model, AutoReverseDiff(compile=true))
```

Available AD backends include:
- `AutoReverseDiff(compile=true)` - ReverseDiff with tape compilation (recommended for most models)
- `AutoForwardDiff()` - ForwardDiff (efficient for models with few parameters)
- `AutoMooncake()` - Mooncake (requires `UseGeneratedLogDensityFunction()` mode)

For fine-grained control, you can configure the AD backend:

```julia
# ReverseDiff without compilation
model = compile(model_def, data; adtype=AutoReverseDiff(compile=false))
```

The compiled model with gradient support implements the [`LogDensityProblems.jl`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/) interface, including [`logdensity_and_gradient`](https://www.tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity_and_gradient), which returns both the log density and its gradient.

### Inference

For gradient-based inference, we use [`AdvancedHMC.jl`](https://github.com/TuringLang/AdvancedHMC.jl) with models compiled with an `adtype`:

```@example abc
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

This is consistent with the result in the [OpenBUGS seeds example](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html).

## Evaluation Modes and Automatic Differentiation

JuliaBUGS supports multiple evaluation modes and AD backends. The evaluation mode determines how the log density is computed, and constrains which AD backends can be used.

### Evaluation Modes

| Mode | AD Backends |
|------|-------------|
| `UseGraph()` (default) | ReverseDiff, ForwardDiff |
| `UseGeneratedLogDensityFunction()` | Mooncake |

- **`UseGraph()`**: Evaluates by traversing the computational graph. Supports user-defined primitives registered via `@bugs_primitive`.
- **`UseGeneratedLogDensityFunction()`**: Generates and compiles a Julia function for the log density.

### AD Backends with `UseGraph()` Mode

Use [ReverseDiff.jl](https://github.com/JuliaDiff/ReverseDiff.jl) or [ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl) with the default `UseGraph()` mode:

```julia
using ADTypes

# ReverseDiff with tape compilation (recommended for large models)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=true))

# ForwardDiff (efficient for small models with < 20 parameters)
model = compile(model_def, data; adtype=AutoForwardDiff())

# ReverseDiff without compilation (supports control flow)
model = compile(model_def, data; adtype=AutoReverseDiff(compile=false))
```

!!! warning "Compiled ReverseDiff does not support control flow"
    Compiled tapes record a fixed execution path. If your model contains value-dependent control flow (e.g., `if x > 0`, `while`, truncation), the tape will only capture one branch and produce **incorrect gradients** when the control flow takes a different path. Use `AutoReverseDiff(compile=false)` or `AutoForwardDiff()` for models with control flow.

### AD Backend with `UseGeneratedLogDensityFunction()` Mode

Use [Mooncake.jl](https://github.com/compintell/Mooncake.jl) with the generated log density function mode:

```julia
using ADTypes

model = compile(model_def, data)
model = set_evaluation_mode(model, UseGeneratedLogDensityFunction())
model = BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
```

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

## More Examples

We have transcribed all the examples from the first volume of the BUGS Examples ([original](https://www.multibugs.org/examples/latest/VolumeI.html) and [transcribed](https://github.com/TuringLang/JuliaBUGS.jl/tree/main/JuliaBUGS/src/BUGSExamples/Volume_1)). All programs and data are included, and can be compiled using the steps described in the tutorial above.
