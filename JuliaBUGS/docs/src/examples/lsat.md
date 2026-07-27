# LSAT: Item Response

This is the classic *LSAT* example from [Volume 1 of the BUGS examples](https://www.multibugs.org/examples/latest/VolumeI.html) (see also the [OpenBUGS write-up](https://chjackson.github.io/openbugsdoc/Examples/Lsat.html)). Section 6 of the Law School Aptitude Test (LSAT) is a 5-item multiple choice test; students score 1 on each item for a correct answer and 0 otherwise, giving 32 possible response patterns. Bock and Lieberman (1970) present data on this test for 1000 students, recorded as the frequency of each of the `R = 32` response patterns.

The question is how to separate the difficulty of each test item from the ability of each student. The data are analysed with the one-parameter **Rasch model**, a foundational item response model: the probability that student `j` answers item `k` correctly follows a logistic function of an item difficulty parameter `alpha[k]` and a latent ability `theta[j]`, with abilities assumed normally distributed in the student population. The scale parameter `beta` (constrained to be positive) governs the spread of the ability distribution. Because the location of the difficulties is only identified relative to the mean ability (fixed at zero), the model also computes centred difficulties `a[k] = alpha[k] - mean(alpha)`, which can be compared with the marginal maximum likelihood estimates of Bock and Aitkin (1981).

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

lsat = @bugs begin
    # Calculate individual (binary) responses to each test from Multinomial data
    for j in 1:culm[1]
        for k in 1:T
            r[j, k] = response[1, k]
        end
    end

    for i in 2:R
        for j in (culm[i - 1] + 1):culm[i]
            for k in 1:T
                r[j, k] = response[i, k]
            end
        end
    end

    # Rasch model
    for j in 1:N
        for k in 1:T
            p[j, k] = logistic(beta * theta[j] - alpha[k])
            r[j, k] ~ dbern(p[j, k])
        end
        theta[j] ~ dnorm(0, 1)
    end

    # Priors
    for k in 1:T
        alpha[k] ~ dnorm(0, 0.0001)
        a[k] = alpha[k] - mean(alpha[:])
    end
    beta ~ dunif(0, 1000)
end
```

## Data

The data are supplied as a `NamedTuple`. `N = 1000` is the number of students, `T = 5` the number of test items, and `R = 32` the number of distinct response patterns. Each row of `response` is one pattern of five 0/1 answers, and `culm` gives the cumulative number of students whose answers match patterns up to and including that row.

```@example lsat
data = (
    N = 1000,
    R = 32,
    T = 5,
    culm = [3, 9, 11, 22, 23, 24, 27, 31, 32, 40, 40, 56, 56, 59, 61, 76, 86, 115,
        129, 210, 213, 241, 256, 336, 352, 408, 429, 602, 613, 674, 702, 1000],
    response = [0 0 0 0 0
                0 0 0 0 1
                0 0 0 1 0
                0 0 0 1 1
                0 0 1 0 0
                0 0 1 0 1
                0 0 1 1 0
                0 0 1 1 1
                0 1 0 0 0
                0 1 0 0 1
                0 1 0 1 0
                0 1 0 1 1
                0 1 1 0 0
                0 1 1 0 1
                0 1 1 1 0
                0 1 1 1 1
                1 0 0 0 0
                1 0 0 0 1
                1 0 0 1 0
                1 0 0 1 1
                1 0 1 0 0
                1 0 1 0 1
                1 0 1 1 0
                1 0 1 1 1
                1 1 0 0 0
                1 1 0 0 1
                1 1 0 1 0
                1 1 0 1 1
                1 1 1 0 0
                1 1 1 0 1
                1 1 1 1 0
                1 1 1 1 1]
)

model = lsat(data)
```

All of the classic examples ship with the package under `JuliaBUGS.BUGSExamples`, bundling the model definition, data, initial values, and reference results (this one is `JuliaBUGS.BUGSExamples.VOLUME_1.lsat`).

## Sampling

To draw posterior samples, construct the model with gradient support and run the No-U-Turn sampler:

```julia
using AbstractMCMC, AdvancedHMC, ADTypes, Mooncake, FlexiChains
using LogDensityProblems

model = lsat(data; adtype=AutoMooncake(; config=nothing))

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

See also: [gallery overview](index.md) and the [getting-started tutorial](../getting_started.md).
