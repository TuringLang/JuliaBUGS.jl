# Leuk: Cox regression

## Description
Several authors have discussed Bayesian inference for censored survival data where the integrated baseline hazard function is to be estimated non-parametrically, including Kalbfleisch (1978), Kalbfleisch and Prentice (1980), Clayton (1991), and Clayton (1994). 
Clayton (1994) formulates the Cox model using counting process notation introduced by Andersen and Gill (1982) and discusses estimation of the baseline hazard and regression parameters using MCMC methods. 
Although this approach may seem somewhat contrived, it lays the groundwork for extensions to random effect (frailty) models, time-dependent covariates, smoothed hazards, multiple events, and more. 
Below is how to implement this formulation of the Cox model in BUGS.

For subjects $i = 1,...,n$, we observe processes $N_i(t)$ which count the number of failures up to time $t$. The corresponding intensity process $I_i(t)$ is given by

$$I_i(t) \, dt = \mathbb{E}[dN_i(t) \, | \, \mathcal{F}_{t-}]$$

where $dN_i(t)$ is the increment of $N_i$ over the interval $[t, t+dt)$, and $\mathcal{F}_{t-}$ represents the available data just before time $t$. If subject $i$ fails during this interval, $dN_i(t) = 1$; otherwise, $dN_i(t) = 0$. Hence, $\mathbb{E}(dN_i(t) | \mathcal{F}_{t-})$ corresponds to the probability of subject $i$ failing in the interval $[t, t+dt)$. As $dt \to 0$, this probability becomes the instantaneous hazard at time $t$ for subject $i$, assumed to have the form

$$I_i(t) = Y_i(t)\lambda_0(t) \exp(\beta z_i)$$

where $Y_i(t)$ is an observed process taking the value 1 or 0 according to whether subject $i$ is at risk at time $t$, and $\lambda_0(t) \exp(\beta z_i)$ is the Cox regression model. Thus, the observed data $D = \{N_i(t), Y_i(t), z_i\}; i = 1,...,n$ and unknown parameters $\beta$ and $\Lambda_0(t) = \int_0^t \lambda_0(u) du$, the latter estimated non-parametrically.

The joint posterior distribution is

$$P(\beta, \Lambda_0() | D) \propto P(D | \beta, \Lambda_0()) P(\beta) P(\Lambda_0())$$

For BUGS, specify the likelihood $P(D | \beta, \Lambda_0())$ and priors for $\beta$ and $\Lambda_0()$. Under non-informative censoring, the data likelihood is

$$\prod_{i=1}^{n} \left( \prod_{t \geq 0} I_i(t) dN_i(t) \right) \exp(- I_i(t) dt)$$

Viewing the increments $dN_i(t)$ as independent Poisson variables with means $I_i(t)dt$:

$$dN_i(t) \sim \text{Poisson}(I_i(t)dt)$$

$$I_i(t)dt = Y_i(t) \exp(\beta z_i) d\Lambda_0(t)$$

where \(d\Lambda_0(t) = \Lambda_0(t)dt\) is the increment or jump in the integrated baseline hazard function occurring during the time interval \([t, t+dt)\). Since the conjugate prior for the Poisson mean is the gamma distribution, it would be convenient if \(\Lambda_0()\) were a process in which the increments \(d\Lambda_0(t)\) are distributed according to gamma distributions. We assume the conjugate independent increments prior suggested by Kalbfleisch (1978), namely   

$$d\Lambda_0(t) \sim \text{Gamma}(c \cdot d\Lambda^*_0(t), c)$$

Here, $d\Lambda^*_0(t)$ can be thought of as a prior guess at the unknown hazard function, with $c$ representing the degree of confidence in this guess. Small values of $c$ correspond to weak prior beliefs. In the example below, we set $d\Lambda^*_0(t) = r \cdot dt$ where $r$ is a guess at the failure rate per unit time, and $dt$ is the size of the time interval.    

The above formulation is appropriate when genuine prior information exists concerning the underlying hazard function. Alternatively, if we wish to reproduce a Cox analysis but with, say, additional hierarchical structure, we may use the Multinomial-Poisson trick described in the BUGS manual. This is equivalent to assuming independent increments in the cumulative `non-informative` priors. This formulation is also shown below.

The fixed effect regression coefficients \(b\) are assigned a vague prior

$$b \sim \text{Normal}(0.0, 0.000001)$$

## BUGS code for the `Leuk` example:

```bugs
model
{
    # Set up data
    for(i in 1:N) {
    for(j in 1:T) {
        # risk set = 1 if obs.t >= t
        Y[i,j] <- step(obs.t[i] - t[j] + eps)
        # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
        # i.e. if t[j] <= obs.t < t[j+1]
        dN[i, j] <- Y[i, j] * step(t[j + 1] - obs.t[i] - eps) * fail[i]
    }
    }
    # Model
    for(j in 1:T) {
        for(i in 1:N) {
            dN[i, j] ~ dpois(Idt[i, j]) # Likelihood
            Idt[i, j] <- Y[i, j] * exp(beta * Z[i]) * dL0[j]    # Intensity
        }
        dL0[j] ~ dgamma(mu[j], c)
        mu[j] <- dL0.star[j] * c # prior mean hazard

        # Survivor function = exp(-Integral{l0(u)du})^exp(beta*z)
        S.treat[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * -0.5));
        S.placebo[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * 0.5));   
    }
    # Priors
    c <- 0.001
    r <- 0.1
    for (j in 1 : T) {
        dL0.star[j] <- r * (t[j + 1] - t[j])
    }
    beta ~ dnorm(0.0,0.000001)
}
```

## Reference Results

| Variable     | Mean   | Median | Standard Deviation | Monte Carlo Error | 2.5% Value | 97.5% Value | Start | Sample | ESS   |
|--------------|--------|--------|--------------------|-------------------|------------|-------------|-------|--------|-------|
| S.placebo[1] | 0.9264 | 0.9374 | 0.04989            | 3.349E-4          | 0.8029     | 0.9909      | 1001  | 20000  | 22184 |
| S.placebo[17] | 0.04431 | 0.03344 | 0.03909         | 2.698E-4          | 0.002478   | 0.1487      | 1001  | 20000  | 20992 |
| S.treat[1]   | 0.9826 | 0.9863 | 0.01413            | 1.074E-4          | 0.9457     | 0.9982      | 1001  | 20000  | 17315 |
| S.treat[17]  | 0.4767 | 0.4763 | 0.1198             | 0.001009          | 0.2474     | 0.7086      | 1001  | 20000  | 14104 |
| beta         | 1.539  | 1.524  | 0.4211             | 0.0034            | 0.7475     | 2.388       | 1001  | 20000  | 15340 |
