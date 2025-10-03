# Methadone: A e-health random effects model with a large number of observations

This example is based on a large linked database of methadone prescriptions given to opioid dependent patients in Scotland, which was used to examine the influence of patient characteristics on doses prescribed (Gao et al. 2016; Dimitropoulou et al. 2017). 
The original dataset is not public, so this example uses a synthetic dataset, simulated to match the key traits of the original dataset.

_The model includes 20,426 random effects in total, and was fitted to 425,112 observations, so will run very slowly unless computation is distributed._

The data have a hierarchical structure, with multiple prescriptions nested within patients within regions. For some of the outcome measurements, person identifiers and person-level covariates are available (240,776 observations). These outcome measurements $y_{ijk}$ represent the quantity of methadone prescribed on occasion $k$ for person $j$ in region $i$ ($i = 1, \ldots, 8$; $j = 1,\ldots,J_i$ ; $k = 1,\ldots,K_{ij}$). Each of these measurements is associated with a binary covariate $r_{ijk}$ (called source.indexed) that indicates the source of prescription on occasion $k$ for person $j$ in region $i$, with $r_{ijk} = 1$ indicating that the prescription was from a General Practitioner (family physician). No person identifiers or person-level covariates are available for the remaining outcome measurements (184,336 observations). We denote by $z_{il}$ the outcome measurement for the $l$th prescription without person identifiers in region $i$ ($i = 1,\ldots,8$; $l = 1,\ldots,L_i$). A binary covariate $s_{il}$ (called source.nonindexed) indicates the source of the $l$th prescription without person identifiers in region $i$, with $s_{il} = 1$ indicating that the prescription was from a General Practitioner (family physician).

The data have been suitably transformed so that fitting a linear model is appropriate, so we model the effect of the covariates with a regression model, with regression parameter $\beta_m$ corresponding to the $m$th covariate $x_{mij}$ ($m = 1, \ldots, 4$), while allowing for within-region correlation via region-level random effects $u_i$, and within-person correlation via person-level random effects $w_{ij}$; source effects $v_i$ are assumed random across regions.

$y_{ijk} = \sum_{m=1}^4 \beta_m x_{mij} + u_i + v_i r_{ijk} + w_{ij} + \varepsilon_{ijk}$

$u_i \sim N(\mu_u, \sigma_u^2)$
$v_i \sim N(\mu_v, \sigma_v^2)$
$w_{ij} \sim N(0, \sigma_w^2)$
$\varepsilon_{ijk} \sim N(0, \sigma_\varepsilon^2)$

The outcome measurements $z_{il}$ contribute only to estimation of regional effects $u_i$ and source effects $v_i$.

$z_{il} = \lambda + u_i + v_i s_{il} + \eta_{il}$

$\eta_{il} \sim N(0, \sigma_\eta^2)$

The error variance $\sigma_\eta^2$ represents a mixture of between-person and between-occasion variation. We assume vague priors for the other parameters.