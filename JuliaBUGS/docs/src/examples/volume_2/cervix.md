# Cervix: case - control study with errors in covariates

What becomes of an estimated odds ratio when the exposure driving it is recorded imperfectly? Carroll, Gail and Lubin (1993) worked that question through on a study of herpes simplex virus (HSV) and invasive cervical cancer, and this example reproduces their analysis. The 2044 women in the data divide into 732 with cancer (`d = 1`) and 1312 without (`d = 0`). Every one of them has a western blot reading `w`, an assay cheap enough to run on the whole sample but wrong often enough to matter, and 115 of them also have `x`, a determination by a more accurate laboratory method; for the remaining 1929 women `x` is `missing` and has to be inferred. Where both readings exist they disagree frequently, and the published analysis found the disagreement to be worse among the controls than among the cases.

The model combines a prospective logistic regression of disease on true exposure with a measurement model for the fallible test. True exposure `x[i]` is itself given a Bernoulli prior with prevalence `q`, so for the 1929 women without a gold-standard reading it is a latent binary variable that the model imputes from `w` and `d`. The probability that `w` comes out positive is allowed to depend on both the true exposure and the disease status, through four parameters $\phi_{j,k} = P(w = 1 \mid x = j - 1,\ d = k - 1)$, which is what lets the model accommodate differential misclassification.

```math
\begin{aligned}
x_i &\sim \text{Bernoulli}(q) \\
d_i &\sim \text{Bernoulli}(p_i), \qquad \text{logit}(p_i) = \beta_{0C} + \beta x_i \\
w_i &\sim \text{Bernoulli}(\phi_{x_i + 1,\ d_i + 1})
\end{aligned}
```

Here $\beta$ is the log odds ratio of disease, the quantity of interest. It and $\beta_{0C}$ are given normal priors with precision $10^{-5}$, following the BUGS convention that the second argument of a normal is a precision; `q` and the four entries of $\phi$ are given uniform priors on the unit interval. The arrays `x1` and `d1` exist only to shift the 0/1 values into the 1/2 range that indexes $\phi$. The derived quantities `gamma1` and `gamma2` are the exposure prevalences among controls and cases, $P(x = 1 \mid d = 0)$ and $P(x = 1 \mid d = 1)$; they are computed from `beta0C`, `beta` and `q` by Bayes' theorem rather than declared as stochastic nodes, because making them depend on `d` directly would introduce a cycle into the graph. Note also that the imputed `x[i]` are discrete latent variables, so they must be summed out or updated by a sampler that supports discrete parameters. This is one of the examples in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Cervix.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.cervix`, which ships with the package.

## Model

```@example volume_2_cervix
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.cervix
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_cervix
print(example.original_syntax_program)
```

## Data

```@example volume_2_cervix
example.data
```

## Compiling the model

```@example volume_2_cervix
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

```@example volume_2_cervix
example.reference_results
```

