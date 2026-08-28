# Pig Weights: Histogram smoothing with structured precision matrix

This example is a histogram-smoothing problem adapted from Congdon (2001), example 5.9. The data are the weight gains of `n = 522` pigs, already grouped into `s = 21` ordered bins, and all that is retained is the count `y` in each bin. The counts rise from 1 in the lowest bin to a peak of 72 around the twelfth and fall away again to 1 in the highest, but the tails are ragged: three bins hold a single pig and two hold none at all. The question is what smooth distribution of weight gain lies behind that noisy histogram.

The counts are multinomial over the 21 bins, and the bin probabilities are the softmax of a vector of logits $\gamma$. Smoothing is imposed entirely through the prior on $\gamma$, which is multivariate normal with a constant mean of $-\log s$ in every bin, corresponding to a flat histogram, and a precision matrix built to represent a first-order autoregressive process along the bin index. Neighbouring bins are therefore pulled towards each other, and the strength of that pull is estimated from the data through $\rho$ rather than fixed by the analyst.

```math
y \sim \text{Multinomial}(\theta, n), \qquad
\theta_i = \frac{e^{\gamma_i}}{\sum_k e^{\gamma_k}}, \qquad
\gamma \sim \text{MVNormal}(\mu, T)
```

The point of interest is how $T$ is written. Rather than forming the AR(1) covariance with entries $\rho^{|i-j|}/\tau$ and inverting it, which the model shows as a commented-out alternative, the precision matrix is specified directly in tridiagonal form: $\tau$ at the two corners of the diagonal, $\tau(1 + \rho^2)$ on the interior diagonal, $-\tau\rho$ on the two off-diagonals, and zero everywhere else. That is the exact inverse of the AR(1) covariance and it avoids a matrix inversion at every iteration, so the same model runs considerably faster. The priors are $\rho \sim \text{Uniform}(0, 1)$, which keeps the correlation between adjacent bins positive, and $\tau \sim \text{Uniform}(0.5, 10)$; note that $\tau$ is a precision here, as it is throughout BUGS. The smoothed bin frequencies `Sm[i]` = $n\,\theta_i$ are the quantities reported. This example is part of Volume 3 of the classic BUGS examples; see the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeIII.html) and the [OpenBUGS Pigweights page](https://chjackson.github.io/openbugsdoc/Examples/Pigweights.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.pig_weights`, which ships with the package.

## Model

```@example volume_3_pig_weights
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.pig_weights
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_pig_weights
print(example.original_syntax_program)
```

## Data

```@example volume_3_pig_weights
example.data
```

## Compiling the model

```@example volume_3_pig_weights
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

```@example volume_3_pig_weights
example.reference_results
```

