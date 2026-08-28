# Orange Trees: Non-linear growth curve

This is the multivariate normal version of the [Orange Trees example](orange_trees.md), and it uses the same data: the trunk circumference of $K = 5$ orange trees, each measured on the same $n = 7$ occasions at $x_j = 118, 484, 664, 1004, 1231, 1372$ and $1582$ days. The measurements grow from around 30 at the first occasion to between 140 and 214 at the last, with the trees differing in both their eventual size and how quickly they approach it.

The likelihood is unchanged. Each observation is normal about a logistic growth curve with tree-specific parameters, written on an unconstrained scale so that the asymptote stays positive and the rate constant negative:

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}(\eta_{ij}, \tau_C) \\
\eta_{ij} &= \frac{\phi_{i1}}{1 + \phi_{i2} \exp(\phi_{i3} x_j)} \\
\phi_{i1} &= \exp(\theta_{i1}), \quad \phi_{i2} = \exp(\theta_{i2}) - 1, \quad \phi_{i3} = -\exp(\theta_{i3})
\end{aligned}
```

What changes is the prior on the tree-level parameters. Instead of three independent univariate normals, the vector $\theta_{i,1:3}$ is drawn from a single trivariate normal, $\theta_{i,1:3} \sim \text{MVN}(\mu, \tau)$, so the model can learn that a tree with a large asymptote also tends to have, say, a particular growth rate rather than treating the three coordinates as unrelated. Following the BUGS convention, `dmnorm` takes a precision matrix rather than a covariance matrix, so the 3-by-3 matrix the program calls `tau` is the inverse covariance of the random effects, not their covariance. It is given a Wishart prior, `dwish(R, 3)` with $R = 0.1 I$ and 3 degrees of freedom, the smallest value admissible for a 3-by-3 matrix and hence the vaguest choice available in this family. The mean vector $\mu$ gets a multivariate normal prior with zero mean and precision $10^{-6} I$, and the residual precision $\tau_C$ a vague gamma prior. The covariance matrix `sigma2` is recovered by inverting `tau`, and `sigma[i]` is the square root of its $i$th diagonal element.

The example appears in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/OtreesMVN.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.orange_trees_multivariate`, which ships with the package.

## Model

```@example volume_2_orange_trees_multivariate
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.orange_trees_multivariate
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_orange_trees_multivariate
print(example.original_syntax_program)
```

## Data

```@example volume_2_orange_trees_multivariate
example.data
```

## Compiling the model

```@example volume_2_orange_trees_multivariate
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

```@example volume_2_orange_trees_multivariate
example.reference_results
```

