# Dugongs: nonlinear growth curve

This example is the nonconjugate analysis of Carlin and Gelfand (1991), working from a data set collected by Ratkowsky (1983). It pairs an age with a length for each of 27 dugongs, or sea cows. The ages $x_i$ run from 1 to 31.5 years and the lengths $Y_i$ from 1.77 to 2.72, one measurement of each per animal. Growth is clearly not linear: length rises quickly over the first few years and then flattens out, so the question is how to describe a curve that decelerates towards a maximum attainable size.

The curve chosen for the mean rises steadily without ever turning over, and levels off at a finite ceiling as the animals age. Each length is normal about a mean that approaches $\alpha$ geometrically, with $\beta$ the total growth from birth to that ceiling and $\gamma$ controlling how fast the curve gets there.

```math
\begin{aligned}
Y_i &\sim \text{Normal}(\mu_i, \tau), \qquad i = 1, \ldots, 27 \\
\mu_i &= \alpha - \beta \gamma^{x_i}, \qquad \alpha, \beta > 0, \; 0 < \gamma < 1
\end{aligned}
```

Here $\tau$ is the precision (inverse variance) of the normal, following the BUGS convention; the derived quantity `sigma` is $1/\sqrt{\tau}$. The prior on $\gamma$ is uniform on $(0.5, 1)$, with $\alpha$ and $\beta$ uniform on $(0, 100)$ and a vague gamma prior on $\tau$. The point of the example is that $\gamma$ enters the mean through an exponent, so its full conditional distribution is neither conjugate nor log-concave, which makes it a standard test case for samplers. The model also monitors $U_3 = \operatorname{logit}(\gamma)$, a transformation on which the posterior is better behaved.

The example appears in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Dugongs.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.dugongs`, which ships with the package.

## Model

```@example volume_2_dugongs
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.dugongs
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_dugongs
print(example.original_syntax_program)
```

## Data

```@example volume_2_dugongs
example.data
```

## Compiling the model

```@example volume_2_dugongs
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

```@example volume_2_dugongs
example.reference_results
```

