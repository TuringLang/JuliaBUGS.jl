# Asia: expert system

This is the chest-clinic network of Lauritzen and Spiegelhalter (1988), a small fictitious expert system for diagnosing a patient who presents with shortness of breath. Seven binary variables are linked in a directed graph: whether the patient recently visited Asia, whether they smoke, whether they have tuberculosis, lung cancer or bronchitis, whether their chest X-ray is abnormal, and whether they suffer dyspnoea. There is no dataset of cases here. What is supplied as "data" are the conditional probability tables for the network, together with the findings for one particular patient: this patient did visit Asia and does have dyspnoea, and everything else is unknown.

Every node is categorical, drawn with `dcat`, and coded with state 1 for "no" and state 2 for "yes". The tables encode the usual epidemiological story. A visit to Asia lifts the probability of tuberculosis from 0.01 to 0.05; smoking, taken to be an even chance a priori, lifts lung cancer from 0.01 to 0.10 and bronchitis from 0.30 to 0.60; an abnormal X-ray is nearly certain if either lung disease is present and unlikely otherwise; and dyspnoea depends jointly on bronchitis and on the presence of either lung disease. The intermediate node `either` is defined as `max(tuberculosis, lung_cancer)`, which under this 1-and-2 coding is exactly a logical OR.

Given the two findings, the inference problem is to work out posterior probabilities for the five unobserved nodes, in effect propagating evidence backwards through the network: the observed dyspnoea and Asia visit make tuberculosis, lung cancer and bronchitis all more plausible than their prior rates, and they also compete with one another to explain the symptom. Because each node takes only the values 1 or 2, a posterior mean reported for it translates directly into a probability: subtract 1 and you have the posterior probability that the node is in its "yes" state. See [Volume 2 of the classic BUGS examples](https://www.multibugs.org/examples/latest/VolumeII.html) and the [OpenBUGS Asia page](https://chjackson.github.io/openbugsdoc/Examples/Asia.html).

The model definition, data, initial values, and published reference results shown here all come from `JuliaBUGS.BUGSExamples.VOLUME_2.asia`, which ships with the package.

## Model

```@example volume_2_asia
using JuliaBUGS

example = JuliaBUGS.BUGSExamples.VOLUME_2.asia
example.model_def
```

The program as it appears in the original BUGS distribution:

```@example volume_2_asia
print(example.original_syntax_program)
```

## Data

```@example volume_2_asia
example.data
```

## Compiling the model

```@example volume_2_asia
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

```@example volume_2_asia
example.reference_results
```

