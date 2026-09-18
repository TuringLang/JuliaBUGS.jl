# Example Gallery

The classic BUGS examples, rewritten as JuliaBUGS pages. Each page states the model, shows
the data, and points at the published reference results, so you can read the model and
reproduce the numbers in one place. If you know these examples from WinBUGS, OpenBUGS, or
JAGS they should feel familiar; the original write-ups live on the MultiBUGS examples pages
for [Volume 1](https://www.multibugs.org/examples/latest/VolumeI.html),
[Volume 2](https://www.multibugs.org/examples/latest/VolumeII.html), and
[Volume 3](https://www.multibugs.org/examples/latest/VolumeIII.html).

Every example ships with the package, so you do not need to retype anything. Each one is
available as `JuliaBUGS.BUGSExamples.VOLUME_N.<key>`, bundling the model definition, the
original BUGS program, the data, two sets of initial values, and, where they were published,
reference results to compare against. The pages below pull everything they show from there.
`JuliaBUGS.BUGSExamples.list()` prints the lot. The files themselves live in the
`BUGSExamples/` directory of the repository, one folder per example.

| Volume | Examples | |
|---|---|---|
| Volume 1 | 20 | [browse](#Volume-1) |
| Volume 2 | 16 | [browse](volume_2/index.md) |
| Volume 3 | 14 | [browse](volume_3/index.md) |

Some examples in the collection use language features JuliaBUGS does not support yet. They
are on disk, marked blocked, and left out of the volumes above, so their pages are absent
rather than broken:

| Example | Blocked by |
|---|---|
| Volume 1, Inhalers | `compile` reports a loop in the graph: the logical node `group[i]` indexes `mu[group[i], t]` |
| Volume 2, Ice | `compile` reports a loop in the graph: `beta[k]` has prior mean `betamean[k]`, which is computed from the neighbouring `beta` |
| Volume 3, Camel | `Y[5, 1:2]` is a partially observed multivariate node, which `compile` rejects |
| Volume 3, Fire | `dloglik` is not an allowed function in `@bugs` |
| Volume 3, Jama and St Veit Klinglberg | `interp.lin` is not an allowed function in `@bugs` |

Volume 4 has one example in the repository, Methadone, whose data hold 240,776 observations.
It is not loaded with the package; `JuliaBUGS.BUGSExamples.load(:methadone)` reads it on
demand.

## One model, three ways to write it

JuliaBUGS accepts a model in three forms, and every example page shows two of them. Here is
Rats in all three. The first is BUGS in Julia clothing, the `@bugs` block: `=` where BUGS
writes `<-`, `for i in`, and the BUGS distribution names. This is the form the
[getting-started tutorial](../getting_started.md) teaches and the form each example page
prints under its Model heading.

```@example three_ways
using JuliaBUGS

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
```

The second is the original BUGS program, unchanged, parsed from a string. This is what each
example page prints under "the program as it appears in the original BUGS distribution", and
it is how the examples are stored. `replace_period=false` keeps dotted names such as `tau.c`
as `var"tau.c"`; the default rewrites them to `tau_c`. See
[Coming from WinBUGS, OpenBUGS, and JAGS](../guides/differences.md) for what the parser
accepts.

```@example three_ways
example = JuliaBUGS.BUGSExamples.VOLUME_1.rats
from_bugs = JuliaBUGS.BUGSModelDef(example.original_syntax_program)
```

The third is a Julia function with the `@model` macro, where the stochastic variables come
in as a named tuple and everything else as ordinary arguments, and any Julia function is
available in the body. The BUGS distribution names come from `JuliaBUGS.BUGSPrimitives`. See
[Choosing `@bugs` or `@model`](../two_macros.md) and
[Defining Models with `@model`](../model_macro.md).

```@example three_ways
using JuliaBUGS.BUGSPrimitives

@model function rats_model(
    (; Y, alpha, beta, tau_c, alpha_c, alpha_tau, beta_c, beta_tau), x, xbar, N, T
)
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

All three compile to a model with the same 65 parameters:

```@example three_ways
using LogDensityProblems

data = example.data
models = (
    rats(data),
    from_bugs(data),
    rats_model((; Y=data.Y), data.x, data.xbar, data.N, data.T),
)
LogDensityProblems.dimension.(models)
```

## Volume 1

| Example | Model |
|---|---|
| [Rats: Normal Hierarchical Model](volume_1/rats.md) | Normal hierarchical (random-effects linear growth curve) model for the weekly weights of 30 young rats. |
| [Pumps: Conjugate Gamma-Poisson Hierarchical Model](volume_1/pumps.md) | Conjugate gamma-Poisson hierarchical model for failure rates of ten power plant pumps |
| [Dogs: Loglinear Model for Binary Data](volume_1/dogs.md) | Loglinear model for binary avoidance-learning data from the Solomon-Wynne dog experiment |
| [Seeds: Random Effect Logistic Regression](volume_1/seeds.md) | Random-effects logistic regression for a 2×2 factorial seed-germination experiment across 21 plates. |
| [Surgical: Institutional Ranking](volume_1/surgical.md) | Independent binomial and hierarchical logistic random-effects models for ranking 12 hospitals by cardiac surgery mortality. |
| [Magnesium: Sensitivity to Prior Distributions in Meta-Analysis](volume_1/magnesium.md) | Random-effects meta-analysis of eight magnesium trials fit under six alternative priors on the between-study variance. |
| [Salm: Extra-Poisson Variation in Dose-Response Study](volume_1/salm.md) | Log-linear Poisson regression with plate-level normal random effects for salmonella mutagenicity dose-response counts. |
| [Equiv: Bioequivalence in a Cross-Over Trial](volume_1/equiv.md) | Normal hierarchical (linear mixed) model assessing bioequivalence of two drug formulations from a two-period cross-over trial. |
| [Dyes: Variance Components Model](volume_1/dyes.md) | One-way random effects model separating between-batch and within-batch variation in dyestuff yield. |
| [Stacks: Robust Regression](volume_1/stacks.md) | Robust linear regression with outlier detection on Brownlee's stack loss data |
| [Epilepsy: Repeated Measures on Poisson Counts](volume_1/epil.md) | Poisson generalized linear mixed model for repeated seizure counts in a randomized epilepsy trial, with subject and subject-by-visit random effects. |
| [Blockers: Random Effects Meta-Analysis of Clinical Trials](volume_1/blockers.md) | Random effects meta-analysis pooling 22 beta-blocker trials of mortality after myocardial infarction. |
| [Oxford: Smooth Fit to Log-Odds Ratios](volume_1/oxford.md) | Hierarchical binomial logistic model smoothing the log-odds ratio of childhood cancer versus prenatal X-ray exposure over birth years. |
| [LSAT: Item Response](volume_1/lsat.md) | Rasch item response model for 1000 students' answers to a 5-item LSAT section |
| [Bones: Latent Trait Model for Multiple Ordered Categorical Responses](volume_1/bones.md) | Latent trait (graded-response item response) model that estimates children's skeletal ages from 34 ordered categorical maturity indicators. |
| [Mice: Weibull Regression](volume_1/mice.md) | Weibull regression survival model for censored mouse photocarcinogenicity data across four treatment groups |
| [Kidney: Weibull Regression with Random Effects](volume_1/kidney.md) | Weibull survival regression with patient-level random effects for censored kidney-infection recurrence times |
| [Leuk: Cox Regression](volume_1/leuk.md) | Cox proportional-hazards survival model in counting-process form for censored leukemia remission times |
| [LeukFr: Cox Regression with Random Effects](volume_1/leukfr.md) | Cox proportional-hazards survival model with a normal pair-level frailty (random effect) for the Freireich leukaemia remission data. |

New to the workflow these pages assume? See [Getting Started](../getting_started.md) for the model-to-samples walkthrough that every example page follows.

Adding an example? The Volume 2 and 3 pages share one structure, and the script that produced it is kept in [issue #533](https://github.com/TuringLang/JuliaBUGS.jl/issues/533) rather than in the repository, since the pages are written and maintained by hand from here.
