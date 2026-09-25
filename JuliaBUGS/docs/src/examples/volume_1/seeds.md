# Seeds: Random Effect Logistic Regression

This is the classic *Seeds* example from [Volume 1 of the BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Seeds.html)). The data come from a seed germination experiment laid out as a 2×2 factorial design across 21 plates. For each plate we record the number of seeds that germinated, `r[i]`, out of the total number of seeds sown, `n[i]`. Two experimental factors are crossed: the seed type (`x1`) and the type of root extract used (`x2`).

The scientific question is how seed type, root extract, and their interaction affect the probability of germination, while acknowledging that plates differ from one another for reasons the covariates do not capture. To handle this extra plate-to-plate variability (over-dispersion relative to a plain binomial model), the model is a **random-effects logistic regression**: each plate gets its own random intercept `b[i]`, drawn from a common normal distribution whose precision `tau` is estimated from the data.

This example demonstrates:

- logistic regression for a factorial experiment,
- random effects for extra-binomial variation,
- translating BUGS link-function syntax into Julia-native syntax, and
- starting a model from supplied initial values.

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.seeds`, which ships with the package.

## Model

Let $p_i$ be the germination probability on plate $i$. The model is

```math
\begin{aligned}
b_i &\sim \text{Normal}(0, \tau) \\
\text{logit}(p_i) &= \alpha_0 + \alpha_1 x_{1i} + \alpha_2 x_{2i} + \alpha_{12} x_{1i} x_{2i} + b_i \\
r_i &\sim \text{Binomial}(n_i, p_i)
\end{aligned}
```

Here ``\alpha_0`` is the baseline log-odds of germination, ``\alpha_1`` and ``\alpha_2`` are the main effects of seed type and root extract, and ``\alpha_{12}`` is their interaction. The plate effects ``b_i`` capture variation left unexplained by those factors. The regression coefficients receive vague priors, as does the random-effect precision `tau`; the derived quantity `sigma = 1 / sqrt(tau)` is the standard deviation of the plate effects.

The model definition as JuliaBUGS holds it, parsed from the BUGS program below. Because Julia treats `f(x) = ...` as a function definition, the BUGS link-function form `logit(p[i]) <- ...` becomes the inverse link (`logistic`) applied on the right-hand side. See [Migrating from WinBUGS, OpenBUGS, and JAGS](../../guides/differences.md) for how BUGS programs are parsed.

```@example seeds
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.seeds
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example seeds
print(example.original_syntax_program)
```

## Graph

The model as a directed graph. Drag a node to rearrange it, or use the pencil to edit the
model and watch the generated BUGS code change with it.

```@raw html
<doodle-ppl class="doodleppl-embed" model="seeds" height="560px"
            theme-from="theme--documenter-dark"></doodle-ppl>
```

## Data

The data are supplied as a `NamedTuple`. `r` and `n` are the germinated and total seed counts on each of the `N = 21` plates, while `x1` and `x2` are the (0/1) indicators for seed type and root extract.

```@example seeds
data = example.data
```

```@example seeds
model = compile(example.model_def, data)
```

## Initial values

The initial values published with the classic example set the regression coefficients to zero and
the random-effect precision to 10:

```@example seeds
inits = example.inits
model = compile(example.model_def, data, inits)
nothing # hide
```

JuliaBUGS draws the omitted plate effects `b` from their prior. See [Initial
Values](../../guides/initialization.md) for partial initialization, array-valued parameters, and the
flat vectors accepted by samplers.

## Sampling

To draw posterior samples, construct the model with gradient support and run the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = compile(example.model_def, data; adtype=AutoMooncake(; config=nothing))

n_samples, n_adapts = 2000, 1000
D = LogDensityProblems.dimension(model)
chain = AbstractMCMC.sample(
    model, NUTS(0.8), n_samples;
    chain_type=VNChain, n_adapts=n_adapts,
    initial_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

## Results

The published reference posterior summaries for this example are:

| Parameter | Mean | Std |
| --- | --- | --- |
| alpha0 | -0.5499 | 0.1965 |
| alpha1 | 0.08902 | 0.3124 |
| alpha12 | -0.841 | 0.4372 |
| alpha2 | 1.356 | 0.2772 |
| sigma | 0.2922 | 0.1467 |

A correctly converged chain's `summarystats` output should match these values up to Monte Carlo error.

```@raw html
<div class="mcmc-run" data-example="seeds"></div>
```

See also: [gallery overview](../index.md), [getting-started tutorial](../../getting_started.md), and
[migration guide](../../guides/differences.md).
