# Dugongs: nonlinear growth curve

Carlin and Gelfand (1991) present a nonconjugate Bayesian analysis of the following data set from Ratkowsky (1983):

| Dugong | 1 | 2 | 3 | 4 | 5 | ... | 26 | 27 |
|--------|---|---|---|---|---|-----|----|----|
| Age (X) | 1.0 | 1.5 | 1.5 | 1.5 | 2.5 | ... | 29.0 | 31.5 |
| Length (Y) | 1.80 | 1.85 | 1.87 | 1.77 | 2.02 | ... | 2.27 | 2.57 |

The data are length and age measurements for 27 captured dugongs (sea cows). Carlin and Gelfand (1991) model this data using a nonlinear growth curve with no inflection point and an asymptote as $X_i$ tends to infinity:

$$ Y_i \sim \text{Normal}(\mu_i, \tau), \quad i = 1, \ldots, 27 $$

$$ m_i = a - \beta \gamma^{X_i} \quad (a, \beta > 0; 0 < \gamma < 1) $$

Standard noninformative priors are adopted for $a$, $\beta$ and $\tau$, and a uniform prior on (0,1) is assumed for $\gamma$. However, this specification leads to a non conjugate full conditional distribution for $\gamma$ which is also non log-concave.
