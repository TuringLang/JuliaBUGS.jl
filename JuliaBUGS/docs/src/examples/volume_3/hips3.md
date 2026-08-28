# Hips3: MC estimates for each strata, allowing for parameter uncertainty in revision hazard, h

Third in the hip-replacement series, this example abandons the patient-level simulation and goes back to the closed-form Markov calculation of [Hips1](hips1.md), whose inputs it inherits unchanged with a single exception. That exception is the age and sex specific revision hazard `h`: the quantity the whole evaluation is most sensitive to, the one that is least well known, and now the only thing in the program that is not a fixed number.

The hazard is given a distribution on the log scale, so that it stays positive:

```math
\log h_k \sim \text{Normal}(\log h_{0,k},\ \tau), \qquad h_k = \exp(\log h_k)
```

Following the BUGS convention the second argument of the normal is a precision, not a variance. Here `tau` is supplied as data at 25, which is a standard deviation of 0.2 on the log-hazard scale, and the prior means `logh0` are the logarithms of the four fixed hazards used in the two previous examples: -6.119, -6.438, -6.377 and -6.725 correspond to hazards of 0.0022, 0.0016, 0.0017 and 0.0012. Everything downstream of `h` is deterministic within an iteration, so each draw of the hazards yields a complete set of exact expected costs, life years and QALYs for all 12 strata.

That separation is the point of the example. The posterior standard deviations of `C[k]`, `BL[k]` and `BQ[k]` here reflect uncertainty about the revision hazard alone, uncontaminated by the individual-level variability that [Hips2](hips2.md) reports, and they turn out to be negligible for life expectancy, which barely depends on whether a hip is ever revised, but appreciable for cost, which is driven directly by the number of revisions. Alongside these, the model recomputes the case-mix mean and variance across strata at every iteration, weighting by `p.strata`, so that heterogeneity between strata and uncertainty about the parameters can be reported side by side. [Hips4](hips4.md) completes the series by estimating the hazard ratio between two prostheses from trial data rather than assuming it. The example is in [Volume 3 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeIII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Hips3.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hips3`, which ships with the package.

## Model

```@example volume_3_hips3
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hips3
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hips3
print(example.original_syntax_program)
```

## Data

```@example volume_3_hips3
example.data
```

## Compiling the model

```@example volume_3_hips3
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

```@example volume_3_hips3
example.reference_results
```

