# Leuk: Cox regression

## Description

Several authors have discussed Bayesian inference for censored survival data where the integrated baseline hazard function is to be estimated non-parametrically, including Kalbfleisch (1978), Kalbfleisch and Prentice (1980), Clayton (1991), and Clayton (1994).
Clayton (1994) formulates the Cox model using counting process notation introduced by Andersen and Gill (1982) and discusses estimation of the baseline hazard and regression parameters using MCMC methods.
Although this approach may seem somewhat contrived, it lays the groundwork for extensions to random effect (frailty) models, time-dependent covariates, smoothed hazards, multiple events, and more.
Below is how to implement this formulation of the Cox model in BUGS.

For subjects $i = 1,...,n$, we observe processes $N_i(t)$ which count the number of failures up to time $t$. The corresponding intensity process $I_i(t)$ is given by

$$I_i(t) \, dt = \mathbb{E}[dN_i(t) | \mathcal{F}_{t-}]$$

where $dN_i(t)$ is the increment of $N_i$ over the interval $[t, t+dt)$, and $\mathcal{F}_{t-}$ represents the available data just before time $t$. If subject $i$ is observed to fail during this interval, $dN_i(t) = 1$; otherwise, $dN_i(t) = 0$. Hence, $\mathbb{E}(dN_i(t) | \mathcal{F}_{t-})$ corresponds to the probability of subject $i$ failing in the interval $[t, t+dt)$. As $dt \to 0$, this probability becomes the instantaneous hazard at time $t$ for subject $i$, assumed to have the form

$$I_i(t) = Y_i(t)\lambda_0(t) \exp(\beta z_i)$$

where $Y_i(t)$ is an observed process taking the value 1 or 0 according to whether $i$ is observed at time $t$, and $\lambda_0(t) \exp(\beta z_i)$ is the familiar Cox regression model. Thus, we have observed data $D = \{N_i(t), Y_i(t), z_i\}; i = 1,...,n$ and unknown parameters $\beta$ and $\Lambda_0(t) = \int_0^t \lambda_0(u) du$, the latter to be estimated non-parametrically.

The joint posterior distribution is

$$P(\beta, \Lambda_0() | D) \sim P(D | \beta, \Lambda_0()) P(\beta) P(\Lambda_0())$$

For BUGS, specify the likelihood $P(D | \beta, \Lambda_0())$ and priors for $\beta$ and $\Lambda_0()$. Under non-informative censoring, the data likelihood is

$$\prod_{i=1}^{n} \left( \prod_{t \geq 0} I_i(t)^{dN_i(t)} \right) \exp(- I_i(t) dt)$$

This is essentially as if the counting process increments $dN_i(t)$ in the time interval $[t, t+dt)$ are independent Poisson random variables with means $I_i(t)dt$:

$$dN_i(t) \sim \text{Poisson}(I_i(t)dt)$$

We may write

$$I_i(t)dt = Y_i(t) \exp(\beta z_i) d\Lambda_0(t)$$

where $d\Lambda_0(t) = \Lambda_0(t)dt$ is the increment or jump in the integrated baseline hazard function occurring during the time interval $[t, t+dt)$. Given that the conjugate prior for the mean of a Poisson distribution is the gamma distribution, it would be convenient if $\Lambda_0()$ were a process in which the increments $d\Lambda_0(t)$ are distributed according to gamma distributions. We assume the conjugate independent increments prior suggested by Kalbfleisch (1978), namely

$$d\Lambda_0(t) \sim \text{Gamma}(c \cdot d\Lambda^*_0(t), c)$$

Here, $d\Lambda^*_0(t)$ can be thought of as a prior guess at the unknown hazard function, with $c$ representing the degree of confidence in this guess. Small values of $c$ correspond to weak prior beliefs. In the example below, we set $d\Lambda^*_0(t) = r \cdot dt$ where $r$ is a guess at the failure rate per unit time, and $dt$ is the size of the time interval.

The above formulation is appropriate when genuine prior information exists concerning the underlying hazard function. Alternatively, if we wish to reproduce a Cox analysis but with, say, additional hierarchical structure, we may use the Multinomial-Poisson trick described in the cumulative `non-informative` priors. This formulation is also shown below.

The fixed effect regression coefficients $\beta$ are assigned a vague prior

$$b \sim \text{Normal}(0.0, 0.000001)$$

## BUGS code for the `Leuk` example

```S
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

## Results

| | mean | median | sd | MC_error | val2.5pc | val97.5pc | start | sample | ESS |
|--------------|-------|--------|-------|----------|----------|-----------|-------|--------|-----|
| S.placebo[1] | 0.9261 | 0.9366 | 0.04975 | 3.619E-4 | 0.8021 | 0.9903 | 1001 | 20000 | 18896 |
| S.placebo[2] | 0.8528 | 0.8619 | 0.06777 | 4.546E-4 | 0.6986 | 0.9582 | 1001 | 20000 | 22221 |
| S.placebo[3] | 0.815 | 0.8227 | 0.07448 | 4.954E-4 | 0.6498 | 0.9357 | 1001 | 20000 | 22600 |
| S.placebo[4] | 0.7411 | 0.7482 | 0.08472 | 6.088E-4 | 0.5593 | 0.8858 | 1001 | 20000 | 19361 |
| S.placebo[5] | 0.6683 | 0.6729 | 0.0917 | 6.832E-4 | 0.4778 | 0.8341 | 1001 | 20000 | 18016 |
| S.placebo[6] | 0.5622 | 0.5645 | 0.09729 | 7.064E-4 | 0.3667 | 0.7441 | 1001 | 20000 | 18969 |
| S.placebo[7] | 0.5284 | 0.5298 | 0.09789 | 6.676E-4 | 0.3335 | 0.7136 | 1001 | 20000 | 21502 |
| S.placebo[8] | 0.4134 | 0.4125 | 0.09427 | 6.543E-4 | 0.2357 | 0.5992 | 1001 | 20000 | 20757 |
| S.placebo[9] | 0.3798 | 0.3778 | 0.09312 | 6.452E-4 | 0.2068 | 0.5665 | 1001 | 20000 | 20829 |
| S.placebo[10] | 0.3195 | 0.3157 | 0.08946 | 6.295E-4 | 0.1605 | 0.5037 | 1001 | 20000 | 20192 |
| S.placebo[11] | 0.2573 | 0.2516 | 0.08436 | 6.17E-4 | 0.111 | 0.4394 | 1001 | 20000 | 18695 |
| S.placebo[12] | 0.2243 | 0.2165 | 0.08181 | 6.195E-4 | 0.087 | 0.4042 | 1001 | 20000 | 17438 |
| S.placebo[13] | 0.1943 | 0.1856 | 0.07767 | 5.888E-4 | 0.0684 | 0.368 | 1001 | 20000 | 17400 |
| S.placebo[14] | 0.1649 | 0.1556 | 0.0731 | 5.552E-4 | 0.05026 | 0.3304 | 1001 | 20000 | 17336 |
| S.placebo[15] | 0.1388 | 0.1288 | 0.06783 | 5.122E-4 | 0.03588 | 0.2967 | 1001 | 20000 | 17536 |
| S.placebo[16] | 0.08618 | 0.07542 | 0.05458 | 4.517E-4 | 0.01312 | 0.2187 | 1001 | 20000 | 14603 |
| S.placebo[17] | 0.04396 | 0.03285 | 0.03866 | 3.223E-4 | 0.002481 | 0.1454 | 1001 | 20000 | 14392 |
| S.treat[1] | 0.9826 | 0.9863 | 0.01388 | 1.191E-4 | 0.946 | 0.9981 | 1001 | 20000 | 13597 |
| S.treat[2] | 0.9644 | 0.9689 | 0.02138 | 1.904E-4 | 0.9107 | 0.9921 | 1001 | 20000 | 12600 |
| S.treat[3] | 0.9545 | 0.9593 | 0.02505 | 2.306E-4 | 0.8933 | 0.9881 | 1001 | 20000 | 11795 |
| S.treat[4] | 0.934 | 0.9398 | 0.03211 | 3.145E-4 | 0.8566 | 0.9795 | 1001 | 20000 | 10422 |
| S.treat[5] | 0.9124 | 0.9185 | 0.03888 | 3.923E-4 | 0.8202 | 0.9701 | 1001 | 20000 | 9823 |
| S.treat[6] | 0.8773 | 0.8843 | 0.04905 | 5.258E-4 | 0.7629 | 0.9529 | 1001 | 20000 | 8704 |
| S.treat[7] | 0.8651 | 0.872 | 0.05248 | 5.787E-4 | 0.7452 | 0.9472 | 1001 | 20000 | 8221 |
| S.treat[8] | 0.8182 | 0.8253 | 0.06451 | 7.32E-4 | 0.6716 | 0.9231 | 1001 | 20000 | 7766 |
| S.treat[9] | 0.8026 | 0.8099 | 0.06854 | 7.908E-4 | 0.6494 | 0.915 | 1001 | 20000 | 7512 |
| S.treat[10] | 0.7716 | 0.7786 | 0.07596 | 8.885E-4 | 0.6046 | 0.8988 | 1001 | 20000 | 7307 |
| S.treat[11] | 0.7344 | 0.7412 | 0.08437 | 0.001006 | 0.5513 | 0.8777 | 1001 | 20000 | 7026 |
| S.treat[12] | 0.7115 | 0.7179 | 0.08865 | 0.001041 | 0.519 | 0.865 | 1001 | 20000 | 7248 |
| S.treat[13] | 0.6884 | 0.694 | 0.09284 | 0.001099 | 0.49 | 0.8508 | 1001 | 20000 | 7133 |
| S.treat[14] | 0.6626 | 0.6685 | 0.097 | 0.001129 | 0.459 | 0.8346 | 1001 | 20000 | 7384 |
| S.treat[15] | 0.6363 | 0.6413 | 0.1014 | 0.001175 | 0.4274 | 0.8194 | 1001 | 20000 | 7448 |
| S.treat[16] | 0.5668 | 0.5704 | 0.1117 | 0.001256 | 0.3436 | 0.7746 | 1001 | 20000 | 7904 |
| S.treat[17] | 0.4767 | 0.4759 | 0.1198 | 0.001259 | 0.2467 | 0.7121 | 1001 | 20000 | 9053 |
| beta | 1.542 | 1.527 | 0.4165 | 0.005079 | 0.7598 | 2.394 | 1001 | 20000 | 6726 |
