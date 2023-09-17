# Rats: a normal hierarchical model

This example is taken from section 6 of *Gelfand et al. (1990)*, and concerns 30 young rats whose
weights were measured weekly for five weeks. Part of the data is shown below, where $Y_{ij}$ is the
weight of the $i^{th}$ rat measured at age $x_j$.

<center>

$$\text{Weights } Y_{ij} \text{ of rat } i \text{ on day } x_j$$
| Rat   | $$x_j=8$$ | $$x_j=15$$ | $$x_j=22$$ | $$x_j=29$$ | $$x_j=36$$ |
|-------|-----------|------------|------------|------------|------------|
| Rat 1 |       151 |        199 |        246 |        283 |        320 |
| Rat 2 |       145 |        199 |        249 |        293 |        354 |
| ...   |       ... |        ... |        ... |        ... |        ... |
| Rat 30|       153 |        200 |        244 |        286 |        324 |

</center>

A plot of the 30 growth curves suggests some evidence of downward curvature.

The model is essentially a random effects linear growth curve
$$
Y_{ij} \sim \text{Normal}\left( a_i + b_i \left( x_j - \bar{x} \right), \tau_c \right)
$$

$$
a_i \sim \text{Normal}\left( a_c, \tau_a \right)
$$

$$
b_i \sim \text{Normal}\left( b_c, \tau_b \right)
$$

where $\bar{x} = 22$, and $\tau$ represents the precision ($\frac{1}{\text{variance}}$) of a normal distribution. We note the
absence of a parameter representing correlation between $a_i$ and $b_i$ unlike in *Gelfand et al. (1990)*.
However, see the *Birats* example in Volume 2 which does explicitly model the covariance
between $a_i$ and $b_i$. For now, we standardize the $x_j$'s around their mean to reduce dependence
between $a_i$ and $b_i$ in their likelihood: in fact, for the full balanced data, complete independence is
achieved. (Note that, in general, prior independence does not force the posterior distributions to
be independent).

$ a_c $, $ \tau_a $, $ b_c $, $ \tau_b $, $ \tau_c $ are given independent "noninformative" priors. Interest particularly focuses on
the intercept at zero time (birth), denoted $ a_0 = a_c - b_c \cdot \bar{x} $.
