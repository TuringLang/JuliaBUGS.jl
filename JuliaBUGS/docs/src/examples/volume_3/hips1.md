# Hips1: Closed form estimates for each strata

This is the first of four linked examples that build up a cost-effectiveness model for total hip replacement, following Spiegelhalter and Best (2003). A patient who receives a primary prosthesis is followed through a Markov model with `S = 5` states over `N = 60` annual cycles, separately for each of `K = 12` age and sex strata. The five states are: alive with the original prosthesis, death at the time of a revision operation, a successful revision in the current cycle, alive after a revision, and death from other causes. Every input is supplied as fixed data: a set-up cost `C0` of 4052 for the primary operation and a further 5290 for each revision, a 1% operative mortality rate `lambda.op`, a 4% annual re-revision rate `rho`, a 12-by-60 table `lambda` of age and sex specific background mortality rates, per-cycle utilities `bq` of 0.938 while stable against decrements of -0.622 and -0.3387 in the cycle of a fatal or a successful revision, and a 6% annual discount rate for both costs (`delta.c`) and health benefits (`delta.b`). The revision hazard is the vector `h`, one value per strata, taking the four values 0.0022, 0.0016, 0.0017 and 0.0012.

The model contains no stochastic nodes at all. It propagates the marginal state distribution forward analytically, one cycle at a time,

```math
\pi_{k,t,s} = \sum_{r=1}^{S} \pi_{k,t-1,r} \, \Lambda_{k,t,r,s}
```

where $\Lambda_{k,t}$ is the transition matrix for strata $k$ at cycle $t$ and the annual revision probability $\gamma_{k,t} = h_k (t-1)$ grows linearly with the years since the operation. Discounted costs, life years and QALYs are then exact expectations, obtained by weighting the state distribution at each cycle by the per-state cost and benefit vectors `c`, `bl` and `bq`. One evaluation of the model gives the answer with no simulation error, which is why the example carries no reference posterior summaries.

The final block averages the strata-specific results over `p.strata`, the distribution of hip replacements across the 12 strata, to give `mean.C`, `mean.BL` and `mean.BQ` along with the matching standard deviations. Those standard deviations describe how much costs and benefits vary between strata, that is, case mix; they are not uncertainty about a parameter, because at this stage the model has none. The three examples that follow relax this in turn: [Hips2](hips2.md) replaces the closed-form expectation with a Monte Carlo simulation of individual patients, [Hips3](hips3.md) puts a distribution on the revision hazard, and [Hips4](hips4.md) synthesises external trial evidence to compare two prostheses. All four are in [Volume 3 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeIII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Hips1.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hips1`, which ships with the package.

## Model

```@example volume_3_hips1
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hips1
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hips1
print(example.original_syntax_program)
```

## Data

```@example volume_3_hips1
example.data
```

## Compiling the model

```@example volume_3_hips1
model = JuliaBUGS.compile(example.model_def, example.data)
```

Initial values for the sampler are bundled too, as `example.inits` (a second set is available as `example.inits_alternative`).

## Sampling

This block is not executed when the documentation is built, so that the
build stays fast; run it locally to reproduce the numbers below.

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, MCMCChains, LogDensityProblems

model = JuliaBUGS.compile(example.model_def, example.data)
model = JuliaBUGS.initialize!(model, example.inits)
ad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
chain = AbstractMCMC.sample(
    ad_model, NUTS(0.8), n_samples;
    chain_type=Chains, n_adapts=n_adapts, discard_initial=n_adapts,
)
summarystats(chain)
```

## Reference results

The posterior summaries published with the original example. A converged
chain should reproduce these up to Monte Carlo error.

```@example volume_3_hips1
example.reference_results
```

