# Biopsies: discrete variable latent class model

Spiegelhalter and Stovin (1983) studied transplanted hearts that were biopsied more than once in a sitting, and this example fits their data. A total of 414 biopsies were taken across $n_s = 157$ sessions, 57 sessions contributing two biopsies and 100 contributing three, and every biopsy was graded on a four-point ordinal scale for evidence of rejection, running from no rejection up to moderate or severe rejection. The data as supplied record, for each session, how many of its biopsies fell into each of the four grades. The problem is that a biopsy samples only a small part of the heart, so two biopsies from the same session can disagree. What is wanted is the distribution of the underlying rejection state and a quantification of how unreliable a single reading is.

The model treats the true rejection state of each session as an unobserved discrete label, which is what makes this a latent class model. Session $i$ has a true grade, the node the program calls `true[i]`, drawn from a population distribution $p$ over the four classes, and its biopsies are then a multinomial sample of size $n_i$ from the row of a misclassification matrix indexed by that true grade.

```math
\begin{aligned}
\text{true}_i &\sim \text{Categorical}(p) \\
\text{biopsies}_{i,1:4} &\sim \text{Multinomial}\left(\text{error}[\text{true}_i, \cdot],\ n_i\right)
\end{aligned}
```

The structure of the `error` matrix encodes the substantive assumption that a biopsy can understate the true state but never overstate it: all entries above the diagonal are fixed to zero, so a session whose true grade is 1 always reads grade 1, a session whose true grade is 2 reads either 1 or 2, and so on. Only the lower-triangular entries are free parameters, and each free row is given a flat Dirichlet prior, as is the class distribution $p$ itself. In the shipped data the fixed entries of `error` are supplied as numbers and the free entries as `missing`.

The example appears in [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html); see also the [OpenBUGS version of this example](https://chjackson.github.io/openbugsdoc/Examples/Biopsies.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.biopsies`, which ships with the package.

## Model

```@example volume_2_biopsies
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.biopsies
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_biopsies
print(example.original_syntax_program)
```

## Data

```@example volume_2_biopsies
example.data
```

## Compiling the model

```@example volume_2_biopsies
model = JuliaBUGS.compile(example.model_def, example.data)
```


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

```@example volume_2_biopsies
example.reference_results
```

