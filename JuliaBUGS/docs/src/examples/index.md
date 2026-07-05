# Example Gallery

These are the classic BUGS Volume 1 examples, rewritten as runnable JuliaBUGS pages. Each page states the model, loads the data, fits it, and shows the results, so you can read the model and reproduce the numbers in one place. If you know these examples from WinBUGS, OpenBUGS, or JAGS, they should feel familiar; the original write-ups live at the [MultiBUGS examples page](https://www.multibugs.org/examples/latest/VolumeI.html).

Every example also ships inside the package, so you do not need to retype anything. Each one is available as `JuliaBUGS.BUGSExamples.VOLUME_1.<key>`, which bundles the model definition, the data, a set of initial values, and reference results you can compare against.

| Example | Model |
|---|---|
| [Rats: Normal Hierarchical Model](rats.md) | Normal hierarchical (random-effects linear growth curve) model for the weekly weights of 30 young rats. |
| [Pumps: Conjugate Gamma-Poisson Hierarchical Model](pumps.md) | Conjugate gamma-Poisson hierarchical model for failure rates of ten power plant pumps |
| [Dogs: Loglinear Model for Binary Data](dogs.md) | Loglinear model for binary avoidance-learning data from the Solomon-Wynne dog experiment |
| [Seeds: Random Effect Logistic Regression](seeds.md) | Random-effects logistic regression for a 2×2 factorial seed-germination experiment across 21 plates. |
| [Surgical: Institutional Ranking](surgical.md) | Independent binomial and hierarchical logistic random-effects models for ranking 12 hospitals by cardiac surgery mortality. |
| [Magnesium: Sensitivity to Prior Distributions in Meta-Analysis](magnesium.md) | Random-effects meta-analysis of eight magnesium trials fit under six alternative priors on the between-study variance. |
| [Salm: Extra-Poisson Variation in Dose-Response Study](salm.md) | Log-linear Poisson regression with plate-level normal random effects for salmonella mutagenicity dose-response counts. |
| [Equiv: Bioequivalence in a Cross-Over Trial](equiv.md) | Normal hierarchical (linear mixed) model assessing bioequivalence of two drug formulations from a two-period cross-over trial. |
| [Dyes: Variance Components Model](dyes.md) | One-way random effects model separating between-batch and within-batch variation in dyestuff yield. |
| [Stacks: Robust Regression](stacks.md) | Robust linear regression with outlier detection on Brownlee's stack loss data |
| [Epilepsy: Repeated Measures on Poisson Counts](epil.md) | Poisson generalized linear mixed model for repeated seizure counts in a randomized epilepsy trial, with subject and subject-by-visit random effects. |
| [Blockers: Random Effects Meta-Analysis of Clinical Trials](blockers.md) | Random effects meta-analysis pooling 22 beta-blocker trials of mortality after myocardial infarction. |
| [Oxford: Smooth Fit to Log-Odds Ratios](oxford.md) | Hierarchical binomial logistic model smoothing the log-odds ratio of childhood cancer versus prenatal X-ray exposure over birth years. |
| [LSAT: Item Response](lsat.md) | Rasch item response model for 1000 students' answers to a 5-item LSAT section |
| [Bones: Latent Trait Model for Multiple Ordered Categorical Responses](bones.md) | Latent trait (graded-response item response) model that estimates children's skeletal ages from 34 ordered categorical maturity indicators. |
| [Mice: Weibull Regression](mice.md) | Weibull regression survival model for censored mouse photocarcinogenicity data across four treatment groups |
| [Kidney: Weibull Regression with Random Effects](kidney.md) | Weibull survival regression with patient-level random effects for censored kidney-infection recurrence times |
| [Leuk: Cox Regression](leuk.md) | Cox proportional-hazards survival model in counting-process form for censored leukemia remission times |
| [LeukFr: Cox Regression with Random Effects](leukfr.md) | Cox proportional-hazards survival model with a normal pair-level frailty (random effect) for the Freireich leukaemia remission data. |

New to the workflow these pages assume? See [Getting Started](../getting_started.md) for the model-to-samples walkthrough that every example page follows.
