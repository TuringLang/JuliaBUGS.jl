# Getting Started

This tutorial takes you from a fresh Julia installation to a fitted Bayesian model. By the end you will have written a hierarchical growth-curve model in BUGS notation, drawn posterior samples from it, and read off posterior summaries that you can check against published results.

## Setup

If you do not have Julia yet, download it from [julialang.org/downloads](https://julialang.org/downloads/); any recent version will do. Then start Julia and install the packages this tutorial uses:

```julia
using Pkg
Pkg.add(["JuliaBUGS", "AbstractMCMC", "AdvancedHMC", "ADTypes", "Mooncake", "FlexiChains"])
```

JuliaBUGS compiles the model. The other packages do the sampling and bookkeeping: AdvancedHMC provides the NUTS sampler, AbstractMCMC runs it, ADTypes and Mooncake supply the gradients that NUTS needs, and FlexiChains stores the posterior draws. Load them all:

```@example getting_started
using JuliaBUGS
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
```

## The model

We will fit *Rats*, the first example in the classic BUGS examples (Volume 1), taken from Gelfand et al. (1990). Thirty young rats were weighed weekly for five weeks, so we have weights ``Y_{ij}`` for rat ``i = 1, \dots, 30`` at ages ``x_j = 8, 15, 22, 29, 36`` days. Each rat grows roughly along a straight line, but rats differ, so each gets its own intercept ``\alpha_i`` and slope ``\beta_i``, and those in turn are drawn from population-level distributions — a normal hierarchical model:

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}\!\left(\alpha_i + \beta_i (x_j - \bar{x}),\ \tau_c\right) \\
\alpha_i &\sim \text{Normal}(\alpha_c,\ \alpha_\tau) \\
\beta_i &\sim \text{Normal}(\beta_c,\ \beta_\tau)
\end{aligned}
```

Here ``\bar{x} = 22`` is the mean age (centering the ages reduces correlation between intercepts and slopes), and — following the BUGS convention — normal distributions are written in terms of a *precision* (1/variance), not a variance.

In JuliaBUGS you write this model with the `@bugs` macro:

```@example getting_started
rats = @bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], tau_c)
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        beta[i] ~ dnorm(beta_c, beta_tau)
    end
    tau_c ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau_c)
    alpha_c ~ dnorm(0.0, 1.0e-6)
    alpha_tau ~ dgamma(0.001, 0.001)
    beta_c ~ dnorm(0.0, 1.0e-6)
    beta_tau ~ dgamma(0.001, 0.001)
    alpha0 = alpha_c - xbar * beta_c
end
nothing # hide
```

If you have used WinBUGS, OpenBUGS, or JAGS, this should look familiar. Reading it line by line:

- `~` means "is distributed as": `Y[i, j] ~ dnorm(mu[i, j], tau_c)` says the weight is normal with mean `mu[i, j]` and precision `tau_c`. Distributions keep their BUGS names (`dnorm`, `dgamma`, and so on).
- `=` defines a deterministic quantity (BUGS uses `<-` for this): `sigma = 1 / sqrt(tau_c)` is the residual standard deviation, computed from the precision, and `alpha0` is the population intercept extrapolated back to birth (age zero).
- `for` loops express repetition over rats and over measurement times — the "plates" of the model. The loop bounds `N` and `T` will come from the data.

The vague `dgamma(0.001, 0.001)` and `dnorm(0.0, 1.0e-6)` priors are the standard noninformative choices from the original example. The result, `rats`, is a model *definition*: it is not tied to any data yet.

## Data

The data is just a `NamedTuple` whose names match the variables the model expects — here the ages `x`, their mean `xbar`, the counts `N` and `T`, and the 30×5 matrix of weights `Y`:

```@example getting_started
data = (
    x = [8.0, 15.0, 22.0, 29.0, 36.0],
    xbar = 22,
    N = 30,
    T = 5,
    Y = [151 199 246 283 320
         145 199 249 293 354
         147 214 263 312 328
         155 200 237 272 297
         135 188 230 280 323
         159 210 252 298 331
         141 189 231 275 305
         159 201 248 297 338
         177 236 285 350 376
         134 182 220 260 296
         160 208 261 313 352
         143 188 220 273 314
         154 200 244 289 325
         171 221 270 326 358
         163 216 242 281 312
         160 207 248 288 324
         142 187 234 280 316
         156 203 243 283 317
         157 212 259 307 336
         152 203 246 286 321
         154 205 253 298 334
         139 190 225 267 302
         146 191 229 272 302
         157 211 250 285 323
         132 185 237 286 331
         160 207 257 303 345
         169 216 261 295 333
         157 205 248 289 316
         137 180 219 258 291
         153 200 244 286 324]
)
nothing # hide
```

If your data lives in the R-style `list()` format used by the classic BUGS systems, it translates directly to a `NamedTuple`; see [Coming from WinBUGS, OpenBUGS, and JAGS](guides/differences.md) for the details.

## Fit the model

Compile the model by calling the definition with the data, switch to the generated log-density evaluator, and attach the automatic-differentiation backend that NUTS needs:

```@example getting_started
model = rats(data)
model = JuliaBUGS.set_evaluation_mode(
    model, JuliaBUGS.UseGeneratedLogDensityFunction()
)
model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
nothing # hide
```

The generated evaluator compiles the model's log density into a Julia function instead of walking the model graph for every evaluation. `BUGSModelWithGradient` then equips that function with Mooncake automatic differentiation so the sampler can follow the gradient of the posterior. This setup has a small up-front compilation cost but makes the repeated evaluations during sampling substantially faster.

Now draw posterior samples with NUTS, the standard gradient-based MCMC sampler:

```@example getting_started
chain = AbstractMCMC.sample(
    model, NUTS(0.8), 3000;
    chain_type = VNChain,
    n_adapts = 1000,
    discard_initial = 1000,
    progress = false, # hide
)
nothing # hide
```

This runs 3000 iterations; the first 1000 are used to tune the sampler and are discarded (`n_adapts` and `discard_initial`), leaving 2000 posterior draws. `chain_type = VNChain` collects the draws into a chain object keyed by variable name. Expect the run to take a few minutes.

## Read the results

`summarystats` prints the familiar table of posterior means, standard deviations, and convergence diagnostics for every quantity in the model:

```@example getting_started
summarystats(chain)
```

The table has a row for each of the 30 intercepts `alpha[i]` and slopes `beta[i]`, but the scientific questions concern the population-level rows:

- `beta_c`, the average growth rate: about 6.2 grams per day (published value 6.186),
- `alpha0`, the average weight extrapolated back to birth: about 106.6 grams (published value 106.6),
- `sigma`, the residual standard deviation of the weight measurements: about 6.1 grams (published value 6.093).

Your numbers will not match the published values to every digit, and they will change slightly each time you run the sampler: posterior means estimated from 2000 draws carry a small Monte Carlo error (reported in the `mcse` column), so agreement to within that error is exactly what success looks like. As a quick health check, `rhat` should be very close to 1 for every row.

That is the whole workflow: write the model with `@bugs`, put the data in a `NamedTuple`, compile it with a suitable evaluation mode and gradient backend, `sample` to fit, and `summarystats` to read the results.

## Where next

- The [Example Gallery](examples/index.md) walks through more classic BUGS models, ready to run.
- The [Seeds example](examples/seeds.md) treats a random-effects logistic regression in more depth, including supplying explicit initial values.
- [Initial Values](guides/initialization.md) explains named, partial, array-valued, and sampler-specific initialization.
- [Coming from WinBUGS, OpenBUGS, and JAGS](guides/differences.md) maps your existing workflow — R `list()` data, initial values, CODA summaries — onto JuliaBUGS.
- [DoodleBUGS](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/) lets you build JuliaBUGS models by drawing the graph, in the spirit of DoodleBUGS from WinBUGS.
