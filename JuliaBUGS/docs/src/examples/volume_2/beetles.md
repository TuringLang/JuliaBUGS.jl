# Beetles: choice of link function

This is a dose-response experiment on beetles, reported by Bliss (1935) and later analysed by Dobson (1983). Eight groups, between 56 and 63 insects each and 481 in total, were exposed to carbon disulphide for five hours at eight increasing concentrations, recorded on a log scale from 1.6907 up to 1.8839. The recorded outcome for each group is simply how many of the exposed beetles died: 6 of 59 at the lowest dose, rising to 60 of 60 at the highest. The question is what dose-response curve describes the kill rate, and the data are unusually informative about that because they span almost the whole range from very few deaths to complete mortality.

The counts are binomial, and the interest of the example is the choice of link function connecting the death probability to dose. The model as shipped uses the logistic link, with the two alternatives the original example compares against, the probit and the complementary log-log, left in place as comments that can be swapped in:

```math
r_i \sim \text{Binomial}(p_i,\ n_i), \qquad \text{logit}(p_i) = \alpha^{*} + \beta \, (x_i - \bar{x})
```

Doses are centred at their mean, $\bar{x} \approx 1.793$, which decorrelates the intercept from the slope and makes the sampler's job much easier; the intercept on the original dose scale is then recovered as $\alpha = \alpha^{*} - \beta \bar{x}$. Both $\alpha^{*}$ and $\beta$ get vague normal priors with precision 0.001, the BUGS normal being parameterised by precision rather than variance. The quantity `rhat[i]` is the fitted expected number of deaths in group $i$, and comparing it group by group with the observed `r[i]` is how the three links are judged against each other. Note that in JuliaBUGS the link is written as an inverse-link function on the right-hand side, `logistic(...)` rather than BUGS's `logit(p[i]) <- ...`, with `phi` and `cexpexp` playing the same role for the other two.

The reference results bundled with the package are those for the logistic link; the source file also carries the published probit and complementary log-log summaries as comments. See [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Beetles page](https://chjackson.github.io/openbugsdoc/Examples/Beetles.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.beetles`, which ships with the package.

## Model

```@example volume_2_beetles
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.beetles
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_beetles
print(example.original_syntax_program)
```

## Data

```@example volume_2_beetles
example.data
```

## Compiling the model

```@example volume_2_beetles
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

```@example volume_2_beetles
example.reference_results
```

