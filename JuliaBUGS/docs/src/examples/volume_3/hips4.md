# Hips4: Bayesian approaches to multiple sources of evidence and uncertainty in complex cost-effectiveness modelling

The last of the four hip-replacement examples puts the whole problem together. [Hips1](hips1.md) evaluated one prosthesis in closed form, [Hips2](hips2.md) replaced that with patient-level simulation, and [Hips3](hips3.md) allowed the revision hazard to be uncertain. Here two prostheses are compared, Charnley and Stanmore, and the difference between them is estimated from external trial data rather than assumed. The evidence is `M = 3` studies, each reporting revisions out of operations in both arms: 1683 of 28525, 7 of 200 and 33 of 208 on Charnley, against 28 of 865, 9 of 213 and 69 of 982 on Stanmore. The studies differ in design, so each carries a quality weight, 0.5, 1 and 0.2 respectively. The cost-effectiveness side keeps all the Hips1 inputs and adds a second column for Stanmore: a higher set-up cost, 4402 against 4052, and a higher revision cost, 5640 against 5290.

The evidence is synthesised on the complementary log-log scale, with a study-specific baseline and half the log hazard ratio placed either side of it, so that the counts in the two arms share a common contrast:

```math
\begin{aligned}
r^C_i &\sim \text{Binomial}(p^C_i, n^C_i), \qquad \text{cloglog}(p^C_i) = \text{base}_i - \tfrac{1}{2}\log\text{HR}_i \\
r^S_i &\sim \text{Binomial}(p^S_i, n^S_i), \qquad \text{cloglog}(p^S_i) = \text{base}_i + \tfrac{1}{2}\log\text{HR}_i \\
\log\text{HR}_i &\sim \text{Normal}(\text{LHR},\ w_i \tau_h)
\end{aligned}
```

In the `@bugs` model the link is written the other way round, as `pC[i] = cexpexp(...)`, using the inverse of the complementary log-log. The study log hazard ratios are random effects around a pooled `LHR`, and, because BUGS parameterises the normal by precision, multiplying the common precision `tauh` by the quality weight $w_i$ makes a low-quality study effectively noisier and so less influential. The between-study standard deviation `sigmah` is given a normal prior with mean 0.2 and precision 400, truncated to positive values, and `HR = exp(LHR)` is the pooled hazard ratio.

That hazard ratio feeds the Markov model. As in Hips3, the Charnley revision hazard in strata $k$ is `h[1, k] = exp(logh[k])` with `logh[k]` normal about `logh0[k]` at precision `tau = 25`, and the Stanmore hazard is simply `h[2, k] = HR * h[1, k]`. The five-state model is then run once per prosthesis per strata, and the two runs are differenced to give incremental costs `C.incr`, incremental QALYs `BQ.incr` and an incremental cost-effectiveness ratio for each strata, plus population versions weighted by `p.strata`. Uncertainty from the trials, from the between-study variation and from the strata hazards all propagates into these quantities at once. The model also evaluates `P.CEA`, the posterior probability that Stanmore is cost-effective, at 100 willingness-to-pay values `KK` from 200 to 20000 pounds per QALY in steps of 200, which traces out a cost-effectiveness acceptability curve. The example is in [Volume 3 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeIII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Hips4.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hips4`, which ships with the package.

## Model

```@example volume_3_hips4
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hips4
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hips4
print(example.original_syntax_program)
```

## Data

```@example volume_3_hips4
example.data
```

## Compiling the model

```@example volume_3_hips4
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

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

```@example volume_3_hips4
example.reference_results
```

