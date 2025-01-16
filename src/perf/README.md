
## Performances: status quo of JuliaBUGS and baselines

### Baseline 1:

```julia
using BangBang, Bijectors
using JuliaBUGS.BUGSPrimitives: dgamma, dnorm

function rats_logdensity_with_for_loops(evaluation_env, params)
    (; alpha, xbar, sigma, alpha0, x, mu, Y, beta) = evaluation_env

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

    alpha0 = alpha_c - xbar * beta_c

    tau_c, logjac_tau_c = Bijectors.with_logabsdet_jacobian(gamma_bijector_inv, params[5])
    log_density += logpdf(dgamma(0.001, 0.001), tau_c) + logjac_tau_c

    sigma = 1 / sqrt(tau_c)

    counter = 6
    for i in 30:-1:1
        beta = BangBang.setindex!!(beta, params[counter], i)
        alpha = BangBang.setindex!!(alpha, params[counter + 1], i)
        counter += 2
    end

    # technically, for normal distributions, we don't need the logjac, but include
    # for consistency
    for i in 1:30
        alpha_i, logjac_alpha_i = Bijectors.with_logabsdet_jacobian(identity, alpha[i])
        log_density += logpdf(dnorm(alpha_c, alpha_tau), alpha_i) + logjac_alpha_i

        beta_i, logjac_beta_i = Bijectors.with_logabsdet_jacobian(identity, beta[i])
        log_density += logpdf(dnorm(beta_c, beta_tau), beta_i) + logjac_beta_i
    end

    for i in 1:30
        for j in 1:5
            mu = BangBang.setindex!!(mu, alpha[i] + beta[i] * (x[j] - xbar), i, j)
        end
    end

    for i in 1:30
        for j in 1:5
            log_density += logpdf(dnorm(mu[i, j], tau_c), Y[i, j])
        end
    end

    return log_density
end

evaluation_env = model.evaluation_env
rats_logdensity_with_for_loops(evaluation_env, param_values)
@benchmark rats_logdensity_with_for_loops($evaluation_env, $param_values)
```

```
BenchmarkTools.Trial: 10000 samples with 128 evaluations per sample.
 Range (min … max):  734.695 ns …  1.437 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     821.289 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   825.103 ns ± 47.710 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▄   ▂▁    ▃▁▁▁▁▂▁▁▁▁▂█▂▁▂▁▂▄▃▂▁▁  ▁▁▁ ▁  ▁                   ▁
  █▇▇▇██████████████████████████████████████████▇██▇▇▆▇▇▆▅▅▅▆▆ █
  735 ns        Histogram: log(frequency) by time       975 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

### Baseline 2 (using `VarName`)

To verify that using `VarName` does not induce type instability.

```julia
using BangBang, Bijectors
using JuliaBUGS.BUGSPrimitives: dgamma, dnorm

function rats_logdensity_with_for_loops_using_varnames(evaluation_env, params)
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

    return log_density
end

evaluation_env = model.evaluation_env
rats_logdensity_with_for_loops_using_varnames(evaluation_env, param_values)
@benchmark rats_logdensity_with_for_loops_using_varnames($evaluation_env, $param_values)
```

```
BenchmarkTools.Trial: 10000 samples with 126 evaluations per sample.
 Range (min … max):  738.095 ns …  1.448 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     829.698 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   826.896 ns ± 26.225 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

   ▁▂                            ▄▅█▃ ▁▁                       ▁
  ▆██▆▆▅▆▆▆▇▇▆▇▆▆▇██▇█▇▇▇██▇▇▇▇▇█████▇█████▇██▇▇▇▇▆▆▆▆▅▅▆▆▆▆█▅ █
  738 ns        Histogram: log(frequency) by time       903 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

### JuliaBUGS

```julia
using JuliaBUGS
using BenchmarkTools
using LogDensityProblems

(; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
model = compile(model_def, data, inits)

# rats has 65 parameters
param_values = rand(65)

@benchmark LogDensityProblems.logdensity($model, $param_values)
```

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation per sample.
 Range (min … max):  39.375 μs …  10.686 ms  ┊ GC (min … max): 0.00% … 99.16%
 Time  (median):     46.792 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   49.191 μs ± 150.253 μs  ┊ GC (mean ± σ):  4.30% ±  1.40%

         ▁▅▇▇▄▂▁▁▁▂▂▅▇█▆▆▅▄▄▂▂                                  
  ▁▁▂▂▃▄▆██████████████████████▇▅▄▄▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁ ▄
  39.4 μs         Histogram: frequency by time         62.1 μs <

 Memory estimate: 60.44 KiB, allocs estimate: 1560.
```



