# LSAT: Item Response

This is the classic *LSAT* example from [Volume 1 of the BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Lsat.html)). Section 6 of the Law School Aptitude Test (LSAT) is a 5-item multiple choice test; students score 1 on each item for a correct answer and 0 otherwise, giving 32 possible response patterns. Bock and Lieberman (1970) present data on this test for 1000 students, recorded as the frequency of each of the `R = 32` response patterns.

The question is how to separate the difficulty of each test item from the ability of each student. The data are analysed with the one-parameter **Rasch model**, a foundational item response model: the probability that student `j` answers item `k` correctly follows a logistic function of an item difficulty parameter `alpha[k]` and a latent ability `theta[j]`, with abilities assumed normally distributed in the student population. The scale parameter `beta` (constrained to be positive) governs the spread of the ability distribution. Because the location of the difficulties is only identified relative to the mean ability (fixed at zero), the model also computes centred difficulties `a[k] = alpha[k] - mean(alpha)`, which can be compared with the marginal maximum likelihood estimates of Bock and Aitkin (1981).

The model definition, data, and initial values shown here come from `JuliaBUGS.BUGSExamples.VOLUME_1.lsat`, which ships with the package.

## Model

Writing $p_{jk}$ for the probability that student $j$ answers item $k$ correctly, the model is

```math
\begin{aligned}
r_{jk} &\sim \text{Bernoulli}(p_{jk}) \\
\operatorname{logit}(p_{jk}) &= \beta\,\theta_j - \alpha_k, \qquad j = 1,\dots,1000;\ k = 1,\dots,5 \\
\theta_j &\sim \text{Normal}(0, 1)
\end{aligned}
```

with vague normal priors on the item difficulties $\alpha_k$ and a flat prior on $(0, 1000)$ for $\beta$.

The data arrive as 32 aggregated response patterns rather than individual answers, so the first part of the program expands them: using the cumulative pattern counts `culm`, it assigns each of the 1000 students the binary response vector of their pattern. This deterministic data transformation is carried over directly from the original BUGS program. As in BUGS generally, the link-function form `logit(p[j, k]) <- ...` is written in Julia by applying the inverse link (`logistic`) on the right-hand side.

```@example lsat
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_1.lsat
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example lsat
print(example.original_syntax_program)
```

## Data

The data are supplied as a `NamedTuple`. `N = 1000` is the number of students, `T = 5` the number of test items, and `R = 32` the number of distinct response patterns. Each row of `response` is one pattern of five 0/1 answers, and `culm` gives the cumulative number of students whose answers match patterns up to and including that row.

```@example lsat
data = example.data
```

```@example lsat
model = compile(example.model_def, data)
```

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
    init_params=rand(D), discard_initial=n_adapts,
)
summarystats(chain)
```

BUGS-style initial values for this example are available as `JuliaBUGS.BUGSExamples.VOLUME_1.lsat.inits` and can be applied with `initialize!(model, inits)`.

## Results

Reference posterior summaries are not bundled with the package for this example (the `reference_results` field of `JuliaBUGS.BUGSExamples.VOLUME_1.lsat` is empty). The published results — posterior summaries for the centred item difficulties `a[1]`–`a[5]` and the scale parameter `beta` — are shown in the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Lsat.html) of this example. A correctly converged chain's `summarystats` output should match those published values up to Monte Carlo error.

See also: [gallery overview](../index.md) and the [getting-started tutorial](../../getting_started.md).
