# Investigation and Improvement of JuliaBUGS' Log Density Evaluation

The task is to improve the performance of JuliaBUGS' log density evaluation. 

Some common code to run

```julia
using AbstractPPL
using BangBang
using BenchmarkTools
using Bijectors
using Distributions
using FunctionWrappers
using JuliaBUGS
using LogDensityProblems
using MacroTools
using Graphs, MetaGraphsNext
using Profile
using JuliaBUGS: dnorm, dgamma

(; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
model = compile(model_def, data, inits)
rand_params = rand(65)
inits_params = JuliaBUGS.getparams(model)
evaluation_env = deepcopy(model.evaluation_env)
```

> We will use `rats` examples through out.

## Ideal performance: with hand-written log density

First, let's establish a baseline with a manually optimized implementation:

```julia
using AbstractPPL: IndexLens
using BangBang, Bijectors
using JuliaBUGS.BUGSPrimitives: dgamma, dnorm

function rats_logdensity(evaluation_env, params)
    gamma_bijector = Bijectors.bijector(dgamma(0.001, 0.001))
    gamma_bijector_inv = Bijectors.inverse(gamma_bijector)

    log_density = 0.0

    beta_tau, logjac_beta_tau = Bijectors.with_logabsdet_jacobian(
        gamma_bijector_inv, params[1]
    )
    log_density += logpdf(dgamma(0.001, 0.001), beta_tau) + logjac_beta_tau

    beta_c, logjac_beta_c = Bijectors.with_logabsdet_jacobian(identity, params[2])
    log_density += logpdf(dnorm(0.0, 1.0e-6), beta_c) + logjac_beta_c

    alpha_tau, logjac_alpha_tau = Bijectors.with_logabsdet_jacobian(
        gamma_bijector_inv, params[3]
    )
    log_density += logpdf(dgamma(0.001, 0.001), alpha_tau) + logjac_alpha_tau

    alpha_c, logjac_alpha_c = Bijectors.with_logabsdet_jacobian(identity, params[4])
    log_density += logpdf(dnorm(0.0, 1.0e-6), alpha_c) + logjac_alpha_c

    xbar = AbstractPPL.get(evaluation_env, VarName{:xbar}())
    alpha0 = alpha_c - xbar * beta_c

    tau_c, logjac_tau_c = Bijectors.with_logabsdet_jacobian(gamma_bijector_inv, params[5])
    evaluation_env = BangBang.setindex!!(evaluation_env, tau_c, VarName{Symbol("tau.c")}())
    log_density += logpdf(dgamma(0.001, 0.001), tau_c) + logjac_tau_c

    sigma = 1 / sqrt(tau_c)

    counter = 6
    for i in 30:-1:1
        beta_i_vn = VarName{:beta}(IndexLens((i,)))
        alpha_i_vn = VarName{:alpha}(IndexLens((i,)))
        beta_i = params[counter]
        alpha_i = params[counter + 1]

        alpha_i, logjac_alpha_i = Bijectors.with_logabsdet_jacobian(identity, alpha_i)
        beta_i, logjac_beta_i = Bijectors.with_logabsdet_jacobian(identity, beta_i)

        log_density += logpdf(dnorm(alpha_c, alpha_tau), alpha_i) + logjac_alpha_i
        log_density += logpdf(dnorm(beta_c, beta_tau), beta_i) + logjac_beta_i

        evaluation_env = BangBang.setindex!!(evaluation_env, beta_i, beta_i_vn)
        evaluation_env = BangBang.setindex!!(evaluation_env, alpha_i, alpha_i_vn)
        counter += 2
    end

    for i in 1:30
        for j in 1:5
            alpha_i = AbstractPPL.get(evaluation_env, VarName{:alpha}(IndexLens((i,))))
            beta_i = AbstractPPL.get(evaluation_env, VarName{:beta}(IndexLens((i,))))
            x_j = AbstractPPL.get(evaluation_env, VarName{:x}(IndexLens((j,))))
            x_bar = AbstractPPL.get(evaluation_env, VarName{:xbar}())
            mu_i_j = alpha_i + beta_i * (x_j - x_bar)
            mu_i_j_vn = VarName{:mu}(IndexLens((i, j)))
            evaluation_env = BangBang.setindex!!(evaluation_env, mu_i_j, mu_i_j_vn)
        end
    end

    for i in 1:30
        for j in 1:5
            mu_i_j = AbstractPPL.get(evaluation_env, VarName{:mu}(IndexLens((i, j))))
            Y_i_j = AbstractPPL.get(evaluation_env, VarName{:Y}(IndexLens((i, j))))
            tau_c = AbstractPPL.get(evaluation_env, VarName{Symbol("tau.c")}())
            log_density += logpdf(dnorm(mu_i_j, tau_c), Y_i_j)
        end
    end

    return log_density, alpha0, sigma # return alpha0 and sigma to avoid them being optimized out
end
```

Let's benchmark this implementation with both random and initial parameters:

```julia
println("With random parameters:")
display(@benchmark rats_logdensity($evaluation_env, $rand_params))
println("\nWith initial parameters:")
display(@benchmark rats_logdensity($evaluation_env, $inits_params))
```

With initial parameters, we see slightly better performance. This might be due to the more structured nature of `inits_params` compared to `rand_params`.

## Current performance of JuliaBUGS: with `evaluate!!`

Now let's look at the current performance in JuliaBUGS:

```julia
@benchmark JuliaBUGS.evaluate!!($model, $rand_params)
```

The current implementation is significantly slower than the hand-written version. Let's investigate why.

### Profiling and trying to understand the source of performance issue

Let's profile the code to identify bottlenecks:

```julia

# @profview here comes with VSCode Julia extension
@profview for _ in 1:1000 # one iteration is too short to see the performance issue
    LogDensityProblems.logdensity(model, rand_params)
end
```

![Profiling Results](../images/image.png)

The red bars in the profiling results indicate type instability issues. Let's examine the type inference:

```julia
@code_warntype JuliaBUGS._tempered_evaluate!!(model, rand_params, 1.0)
```

## Key Type Instability Issues

1. `node_function` is stored as a generic `Function` in a `Vector{Function}` and retrieved by index
2. At compile-time, there's no way to know which concrete function will be called
3. This forces dynamic dispatch and causes the return value to be inferred as `Any`
4. The type instability propagates through:
   - `value` from `node_function` call
   - `evaluation_env` updates via `BangBang.setindex!!`
   - `dist` calculations and subsequent `logpdf` operations
:::