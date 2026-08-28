# Hips2: MC estimates for each strata

The second of the four hip-replacement examples changes the arithmetic rather than the model. The clinical setting, the data and the transition structure are exactly those of [Hips1](hips1.md): the same 5-state Markov model over 60 annual cycles for each of 12 age and sex strata, the same fixed revision hazards `h`, operative mortality `lambda.op` of 1%, re-revision rate `rho` of 4%, background mortality table `lambda`, state costs `c`, life-year weights `bl`, utilities `bq`, and 6% discounting of both costs and benefits. What changes is how the expected cost and benefit are worked out.

Instead of propagating the marginal state distribution analytically, this version simulates one individual patient per strata at every iteration. The state occupied at cycle $t$ is a one-trial multinomial draw, and the probabilities for the next draw are read off the row of the transition matrix belonging to the state just occupied:

```math
\pi_{k,t,s} = \sum_{r=1}^{S} y_{k,t-1,r} \, \Lambda_{k,t,r,s}, \qquad
y_{k,t,\cdot} \sim \text{Multinomial}(\pi_{k,t,\cdot},\, 1)
```

Because $y_{k,t-1,\cdot}$ is an indicator vector, the inner product simply selects a row, so the trajectory is a genuine random walk through the five states. Costs and benefits are then accumulated along that one simulated path rather than integrated over the state distribution, and the multinomial draws are the only stochastic nodes in the model.

The two formulations answer the same question in different currencies. Posterior means of `C[k]`, `BL[k]` and `BQ[k]` are Monte Carlo estimates of the closed-form expectations that Hips1 computes exactly, and should agree with them up to Monte Carlo error. Their posterior standard deviations, however, measure something Hips1 cannot express: the spread between individual patients within a strata, which is substantial for life expectancy and for the cost of a revision that either does or does not occur. Parameter uncertainty is still absent, and is taken up in [Hips3](hips3.md) and [Hips4](hips4.md). The example is in [Volume 3 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeIII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Hips2.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hips2`, which ships with the package.

## Model

```@example volume_3_hips2
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hips2
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hips2
print(example.original_syntax_program)
```

## Data

```@example volume_3_hips2
example.data
```

## Compiling the model

```@example volume_3_hips2
model = JuliaBUGS.compile(example.model_def, example.data)
```


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

```@example volume_3_hips2
example.reference_results
```

