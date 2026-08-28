# Hepatitis: a normal hierarchical model with measurement error (basic)

Spiegelhalter et al. (1996) follow 106 children after hepatitis B vaccination, tracking how the anti-Hb titre each child mounts decays over the months that follow. Titres and measurement times are both recorded on a log scale. The response `Y` is a 106-by-3 matrix: 76 children were measured three times and the remaining 30 twice, so the third column holds 30 `missing` entries and there are 288 observed titres in all. The matrix `t` gives the matching log measurement times, with the value 10 standing in wherever the corresponding titre is missing. A single baseline covariate `y0`, the log titre recorded at vaccination, is available for every child. The question is how quickly the titre falls away after vaccination and whether a child's baseline level predicts the level thereafter.

The model is a random-effects linear growth curve. Each child gets an individual intercept $\alpha_i$ and an individual slope $\beta_i$ against log time centred at 6.5, and those child-level coefficients are drawn from common population normals, so a child measured only twice still borrows strength from the rest of the sample. The baseline covariate enters through a single population-level coefficient $\gamma$ on the centred log baseline titre. Following the BUGS convention the second argument of `dnorm` is a precision, not a variance, so $\tau$ is the inverse of the residual variance and `sigma` is recovered from it as $1/\sqrt{\tau}$.

```math
\begin{aligned}
Y_{ij} &\sim \text{Normal}\left(\alpha_i + \beta_i (t_{ij} - 6.5) + \gamma\,(y_{0i} - \bar{y}_0),\ \tau\right) \\
\alpha_i &\sim \text{Normal}(\alpha_0, \tau_\alpha) \\
\beta_i &\sim \text{Normal}(\beta_0, \tau_\beta)
\end{aligned}
```

The population parameters $\alpha_0$, $\tau_\alpha$, $\beta_0$, $\tau_\beta$, $\gamma$, and $\tau$ are given independent very flat conjugate priors. No correlation between $\alpha_i$ and $\beta_i$ is modelled here; the Birats example in Volume 2 shows the version that does. The baseline reading `y0` is itself a titre measurement and so carries the same measurement error as the readings it is used to predict, which biases $\gamma$ towards zero when it is treated as a known covariate. [Hepatitis ME](hepatitis_me.md) is the same study fitted with that error modelled explicitly. This example is part of Volume 3 of the classic BUGS examples; see the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeIII.html) and the [OpenBUGS Hepatitis page](https://chjackson.github.io/openbugsdoc/Examples/Hepatitis.html), which carries both versions.

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_3.hepatitis`, which ships with the package.

## Model

```@example volume_3_hepatitis
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_3.hepatitis
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_3_hepatitis
print(example.original_syntax_program)
```

## Data

```@example volume_3_hepatitis
example.data
```

## Compiling the model

```@example volume_3_hepatitis
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

```@example volume_3_hepatitis
example.reference_results
```

