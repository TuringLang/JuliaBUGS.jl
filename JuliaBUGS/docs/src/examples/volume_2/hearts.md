# Hearts: a mixture model for count data

This example uses data reported by Berry (1987) on 12 patients treated with a drug for frequent premature ventricular contractions (PVCs) of the heart. For each patient the data give the PVC count recorded before the drug was administered, `x`, and the count recorded afterwards, `y`. The pre-drug counts range from 5 to 51, and seven of the twelve patients recorded no PVCs at all after treatment. The question is how much the drug reduces the PVC rate, and in particular whether it suppresses the contractions entirely in some patients rather than merely lowering the rate in all of them.

Following Farewell and Sprott (1988), the counts are treated as coming from two kinds of patient: those in whom the drug has suppressed the contractions altogether, and those whose rate it has merely reduced by some amount. Conditioning each patient's post-drug count on the total $t_i = x_i + y_i$ eliminates the patient-specific Poisson rates and leaves a binomial likelihood, which is what the model codes. The awkwardness is that the two kinds of patient cannot be told apart from the data alone. An observed zero is equally consistent with complete suppression and with a rate that is merely low and happened to yield nothing over the observation period, so which group a patient belongs to has to be inferred rather than read off. The indicator `state[i]`, written $s_i$ below, says which mixture component patient $i$ belongs to, selecting a success probability of $p$ when it is 0 and of exactly 0 when it is 1.

```math
\begin{aligned}
y_i &\sim \text{Binomial}(P_{s_i + 1},\ t_i), \qquad t_i = x_i + y_i \\
s_i &\sim \text{Bernoulli}(\theta) \\
P_1 &= p, \qquad P_2 = 0 \\
\text{logit}(p) &= \alpha, \qquad \text{logit}(\theta) = \delta
\end{aligned}
```

Both $\alpha$ and $\delta$ are given vague $\text{Normal}(0, 10^{-4})$ priors, where the second argument is a precision in the BUGS convention, so a standard deviation of 100 on the logit scale. The derived quantity $\beta = \exp(\alpha)$ is the ratio of the post-drug to the pre-drug PVC rate among uncured patients, and $\theta$ is the probability of a cure. Note that `state[i]` is a discrete latent variable, so a gradient-based sampler cannot update it directly; it has to be summed out, or updated by a sampler that supports discrete parameters. This is one of the examples in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Hearts.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.hearts`, which ships with the package.

## Model

```@example volume_2_hearts
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.hearts
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_hearts
print(example.original_syntax_program)
```

## Data

```@example volume_2_hearts
example.data
```

## Compiling the model

```@example volume_2_hearts
model = JuliaBUGS.compile(example.model_def, example.data, example.inits)
```

The example's own initial values are passed in here. Several of these models fail from random starting values, so `example.inits` is not optional in practice; a second set is available as `example.inits_alternative`.

See [Getting Started](../../getting_started.md) for the recipe that takes a compiled model to posterior samples.

## Reference results

The posterior summaries published with the original example. A
converged chain should reproduce these up to Monte Carlo error.

```@example volume_2_hearts
example.reference_results
```
