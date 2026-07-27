# Rats: Normal Hierarchical Model

This example is taken from section 6 of Gelfand et al. (1990) and concerns 30 young rats whose weights were measured weekly for five weeks. Each rat therefore contributes five weight measurements $Y_{ij}$, taken at ages $x_j = 8, 15, 22, 29, 36$ days. The question is how to describe the growth of the population as a whole while allowing each animal its own growth trajectory: a plot of the 30 growth curves suggests broadly linear growth with some evidence of downward curvature and clear rat-to-rat variation in both starting weight and growth rate.

The model is a random-effects linear growth curve — a normal hierarchical model in which each rat has its own intercept and slope, and these rat-level coefficients are in turn drawn from common population distributions. The ages are centred at their mean $\bar{x} = 22$ to reduce dependence between the intercepts and slopes. Interest focuses in particular on the population intercept at birth (age zero), $\alpha_0 = \alpha_c - \beta_c \bar{x}$. It is the first example in [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Rats.html).

## Model

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}\left(\alpha_i + \beta_i (x_j - \bar{x}),\ \tau_c\right) \\
\alpha_i &\sim \text{Normal}(\alpha_c, \tau_\alpha) \\
\beta_i &\sim \text{Normal}(\beta_c, \tau_\beta)
\end{aligned}
```

where $\tau$ denotes the precision (inverse variance) of a normal distribution, following the BUGS convention. The population parameters $\alpha_c$, $\tau_\alpha$, $\beta_c$, $\tau_\beta$, and $\tau_c$ are given independent "noninformative" priors.

```@example rats
using JuliaBUGS

rats = @bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")
    end
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")
    var"alpha.c" ~ dnorm(0.0, 1.0e-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0e-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    alpha0 = var"alpha.c" - xbar * var"beta.c"
end
```

Names such as `var"tau.c"` are the R-style dotted variable names from the original BUGS program, written with Julia's `var"..."` syntax so they can be kept exactly as they appear in the classic example.

## Data

The data are supplied as a `NamedTuple`: the measurement ages `x`, their mean `xbar`, the number of rats `N`, the number of measurement occasions `T`, and the 30-by-5 matrix `Y` of weights.

```@example rats
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

model = rats(data)
```

All of the classic examples ship with the package in `JuliaBUGS.BUGSExamples`, so the model definition, data, initial values, and reference results above are also available directly as `JuliaBUGS.BUGSExamples.VOLUME_1.rats`.

## Sampling

We draw posterior samples with the NUTS sampler from AdvancedHMC, rebuilding the model with gradient support first.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = rats(data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.rats.inits` and can be applied with `initialize!(model, inits)`.

## Results

The published reference posterior summaries for this example are:

| Parameter | Mean  | Std    |
|-----------|-------|--------|
| `alpha0`  | 106.6 | 3.66   |
| `beta.c`  | 6.186 | 0.1086 |
| `sigma`   | 6.093 | 0.4643 |

A correctly converged chain's `summarystats` should reproduce these values up to Monte Carlo error.

See also: the [example gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
