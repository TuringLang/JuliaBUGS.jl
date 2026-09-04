# Eye Tracking: dirichlet process prior

This example is adapted from Congdon (2001), example 6.27. The data are 101 counts from an eye-tracking study, one per subject. The counts are very unevenly spread: 46 of the 101 subjects contribute a zero, most of the rest are small, and a thin right tail runs out to 34. A single Poisson rate cannot describe that shape, and there is no covariate to explain it, so the question is how many distinct rate levels the subjects fall into and what those levels are.

The model answers this with a Poisson mixture whose mixing distribution is given a Dirichlet process prior, truncated at `C = 10` components and written in its constructive stick-breaking form. Each subject carries a latent label $S_i$ drawn from the mixture weights, and the count is Poisson with the rate belonging to that label's component. The weights are built from independent $r_j \sim \text{Beta}(1, \alpha)$ variables, where $\alpha$ is the precision parameter of the Dirichlet process, fixed at 1 here (a `dgamma(0.1, 0.1)` prior on it is included in the program as a commented-out alternative). Because the stick is cut off after `C` pieces the raw weights `p` do not quite sum to one, so they are rescaled by their own sum. The component rates come from a common $\text{Gamma}(A, B)$ prior with $A$ and $B$ themselves estimated, which lets the data decide how spread out the rate levels are.

```math
\begin{aligned}
x_i &\sim \text{Poisson}(\theta_{S_i}), \qquad S_i \sim \text{Categorical}(\pi) \\
\theta_j &\sim \text{Gamma}(A, B), \qquad r_j \sim \text{Beta}(1, \alpha) \\
\pi_j &= p_j \Big/ \textstyle\sum_k p_k, \qquad p_j = r_j \prod_{l < j} (1 - r_l)
\end{aligned}
```

The number of components actually used is recovered as a derived quantity rather than being fixed in advance: `SC[i, j]` indicates that subject `i` was assigned to component `j`, `sumSC[j]` is the resulting size of component `j`, `cl[j]` is 1 when that component is occupied, and `K` is their sum. One caveat about the reference summaries shown further down: the source ships two published sets, and `example.reference_results`, the set rendered below, is the run in which $A$ and $B$ were held fixed. The model as coded samples them, and the matching figures for that version are recorded as `reference_results_variable` in the example's source file, `src/BUGSExamples/Volume_3/02_Eye_Tracking.jl`, where $K$ averages 7.35 rather than 6.92. This example is part of Volume 3 of the classic BUGS examples; see the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeIII.html) and the [OpenBUGS Eyetracking page](https://chjackson.github.io/openbugsdoc/Examples/Eyetracking.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.eye_tracking`, which ships with the package.

## Model

```@example volume_3_eye_tracking
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.eye_tracking
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_eye_tracking
print(example.original_syntax_program)
```

## Data

```@example volume_3_eye_tracking
example.data
```

## Compiling the model

```@example volume_3_eye_tracking
model = JuliaBUGS.compile(example.model_def, example.data)
```

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_3_eye_tracking
example.reference_results
```
