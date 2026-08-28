# Eyes: Normal Mixture Model

This example uses peak sensitivity wavelengths from microspectrophotometric records of a single monkey's eyes, from the study of Bowmaker et al. (1985). There are $N = 48$ measurements, running from 529.0 to 553.2 nanometres. (The original write-up subtracts 500 from each value; the data bundled here are the untransformed wavelengths.) Plotted as a histogram the measurements are bimodal, which is what one would expect if the records came from two distinct types of photoreceptor rather than one. The question is whether the data really support two groups, and if so where the two peaks sit and in what proportion the records are split between them.

The model is a two-component normal mixture with a common precision. Each observation belongs to an unobserved group $T_i$, and given that group it is normal about the corresponding component mean:

```math
\begin{aligned}
y_i &\sim \text{Normal}(\lambda_{T_i}, \tau) \\
T_i &\sim \text{Categorical}(P), \qquad P \sim \text{Dirichlet}(1, 1)
\end{aligned}
```

As always in BUGS, $\tau$ is a precision rather than a variance, and `sigma` is the derived standard deviation $1/\sqrt{\tau}$. Mixture models of this kind are only identified up to a relabelling of the components, and there is a further danger that the sampler collapses to a state where every observation is assigned to one component. Two devices in the model guard against this. The component means are ordered by construction, $\lambda_1$ getting a vague normal prior and $\lambda_2 = \lambda_1 + \theta$ with $\theta \sim \text{Uniform}(0, 1000)$, so the second component is always the one with the larger mean. And the group labels of the smallest and largest observations are fixed in the data, `T[1] = 1` and `T[48] = 2`, which keeps both components occupied.

The example appears in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Eyes.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.eyes`, which ships with the package.

## Model

```@example volume_2_eyes
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.eyes
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_eyes
print(example.original_syntax_program)
```

## Data

```@example volume_2_eyes
example.data
```

## Compiling the model

```@example volume_2_eyes
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

```@example volume_2_eyes
example.reference_results
```

