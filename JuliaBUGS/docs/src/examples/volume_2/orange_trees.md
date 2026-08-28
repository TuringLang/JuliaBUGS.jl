# Orange Trees: Non-linear growth curve

This example uses the orange tree growth data of Draper and Smith (1981), later reanalysed by Lindstrom and Bates (1990). The trunk circumference of each of $K = 5$ trees was recorded on the same $n = 7$ occasions, at $x_j = 118, 484, 664, 1004, 1231, 1372$ and $1582$ days, giving a 5-by-7 matrix $Y$ of measurements that grow from around 30 at the first occasion to between 140 and 214 at the last. The trees follow visibly similar S-shaped trajectories but differ in how large they get and how quickly they get there, so the question is how to estimate a common growth pattern while letting each tree have its own curve.

The model is a logistic growth curve fitted as a nonlinear random-effects model. Tree $i$ has three parameters $\phi_{i1}, \phi_{i2}, \phi_{i3}$: an asymptotic circumference, a term setting the size at time zero, and a negative rate constant.

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}(\eta_{ij}, \tau_C) \\
\eta_{ij} &= \frac{\phi_{i1}}{1 + \phi_{i2} \exp(\phi_{i3} x_j)}
\end{aligned}
```

Each $\phi$ is a fixed transformation of an unconstrained parameter $\theta$, namely $\phi_{i1} = \exp(\theta_{i1})$, $\phi_{i2} = \exp(\theta_{i2}) - 1$ and $\phi_{i3} = -\exp(\theta_{i3})$. The transformations do the work of the constraints: whatever value $\theta$ takes, the asymptote stays positive and the rate constant stays negative, so the curve is always increasing towards a finite limit. The random effects are placed on the unconstrained scale, with $\theta_{ik} \sim \text{Normal}(\mu_k, \tau_k)$ independently for $k = 1, 2, 3$, and the population parameters $\mu_k$, $\tau_k$ and the residual precision $\tau_C$ are given vague priors. As elsewhere in BUGS, the second argument of a normal is a precision rather than a variance, and the reported `sigma` quantities are the corresponding standard deviations.

The example appears in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Otrees.html) and the [multivariate variant](orange_trees_multivariate.md), which replaces the three independent normal priors with a single multivariate normal.

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.orange_trees`, which ships with the package.

## Model

```@example volume_2_orange_trees
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.orange_trees
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_orange_trees
print(example.original_syntax_program)
```

## Data

```@example volume_2_orange_trees
example.data
```

## Compiling the model

```@example volume_2_orange_trees
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

```@example volume_2_orange_trees
example.reference_results
```

