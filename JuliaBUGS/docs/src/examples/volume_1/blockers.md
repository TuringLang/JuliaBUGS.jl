# Blockers: Random Effects Meta-Analysis of Clinical Trials

This example pools the results of 22 randomized clinical trials of beta-blockers for preventing death after myocardial infarction, originally analysed by Carlin (1992). Each trial reports the number of deaths among the treated patients (`rt` out of `nt`) and among the control patients (`rc` out of `nc`). Individually the trials are of very different sizes — from a few dozen patients to nearly two thousand per arm — so a meta-analysis is needed to combine them into a single estimate of the treatment effect.

The model is a random-effects meta-analysis on the log-odds scale. Each trial has its own baseline log odds of death and its own treatment effect (a log odds ratio), and the trial-specific effects are assumed to be drawn from a common normal population. The population mean `d` is the pooled treatment effect — a negative value means beta-blockers reduce the odds of death — while `delta.new` is the predicted effect in a hypothetical new trial drawn from the same population. It is one of the examples from [Volume 1 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html); the original write-up is also available in the [OpenBUGS documentation](https://chjackson.github.io/openbugsdoc/Examples/Blockers.html).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.blockers`, which ships with the package.

## Model

For trial ``i``, with ``r^c_i`` deaths among ``n^c_i`` control patients and ``r^t_i`` deaths among ``n^t_i`` treated patients:

```math
\begin{aligned}
r^c_i &\sim \text{Binomial}(p^c_i,\, n^c_i), \qquad \operatorname{logit}(p^c_i) = \mu_i \\
r^t_i &\sim \text{Binomial}(p^t_i,\, n^t_i), \qquad \operatorname{logit}(p^t_i) = \mu_i + \delta_i \\
\delta_i &\sim \text{Normal}(d,\, \sigma^2), \qquad i = 1, \ldots, 22
\end{aligned}
```

with vague priors on the trial baselines ``\mu_i``, the pooled effect ``d``, and the between-trial precision ``\tau = 1/\sigma^2``. As always in BUGS, `dnorm` is parameterized by mean and precision, which is why the code below recovers the between-trial standard deviation as `sigma = 1 / sqrt(tau)`.

The model definition as JuliaBUGS holds it, parsed from the BUGS program below:

```@example blockers
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.blockers
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example blockers
print(example.original_syntax_program)
```

The original BUGS program uses the R-style dotted name `delta.new`; in Julia such names are written with the `var"delta.new"` syntax, and they refer to exactly the same variable.

## Data

The data are a `NamedTuple` with, for each of the 22 trials, the deaths and patient counts in the treated arm (`rt`, `nt`) and in the control arm (`rc`, `nc`), plus the number of trials `Num`. Calling the model definition with the data builds the model:

```@example blockers
data = example.data
```

```@example blockers
model = compile(example.model_def, data)
```

## Sampling

To draw posterior samples, rebuild the model with gradient support and run the NUTS sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.blockers.inits` and can be applied with `initialize!(model, inits)`.

## Results

Reference posterior summaries are not bundled with the package for this example; the published results table can be found on the [OpenBUGS Blockers page](https://chjackson.github.io/openbugsdoc/Examples/Blockers.html). The quantities of interest are the pooled treatment effect `d`, the predictive effect for a new trial `var"delta.new"`, and the between-trial standard deviation `sigma`. A correctly converged chain's `summarystats(chain)` should match the published values up to Monte Carlo error.

See also: the [example gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
