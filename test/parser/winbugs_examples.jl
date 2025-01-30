# here are almost all the examples from the first three volume of BUGS examples
# we keep them as basic regression tests for the parser
@testset "Parse BUGS Example Programs" begin

    # rats
    parse_bugs("""model
{
    for( i in 1 : N ) {
        for( j in 1 : T ) {
           Y[i , j] ~ dnorm(mu[i , j],tau.c)
           mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
        }
        alpha[i] ~ dnorm(alpha.c,alpha.tau)
        beta[i] ~ dnorm(beta.c,beta.tau)
     }
     tau.c ~ dgamma(0.001,0.001)
     sigma <- 1 / sqrt(tau.c)
     alpha.c ~ dnorm(0.0,1.0E-6)   
     alpha.tau ~ dgamma(0.001,0.001)
     beta.c ~ dnorm(0.0,1.0E-6)
     beta.tau ~ dgamma(0.001,0.001)
     alpha0 <- alpha.c - xbar * beta.c   
}
""")

    # oxford
    parse_bugs(
        """
model
   {
      for (i in 1 : K) {
         r0[i] ~ dbin(p0[i], n0[i])
         r1[i] ~ dbin(p1[i], n1[i])
         logit(p0[i]) <- mu[i]
         logit(p1[i]) <- mu[i] + logPsi[i]
         logPsi[i] <- alpha + beta1 * year[i] + beta2 * (year[i] * year[i] - 22) + b[i]
         b[i] ~ dnorm(0, tau)
         mu[i] ~ dnorm(0.0, 1.0E-6)
         cumulative.r0[i] <- cumulative(r0[i], r0[i])
         cumulative.r1[i] <- cumulative(r1[i], r1[i])
      }
      alpha ~ dnorm(0.0, 1.0E-6)
      beta1 ~ dnorm(0.0, 1.0E-6)
      beta2 ~ dnorm(0.0, 1.0E-6)
      tau ~ dgamma(1.0E-3, 1.0E-3)
      sigma <- 1 / sqrt(tau)
   }
"""
    )

    # inhalers
    parse_bugs(
        """
model
{
#
# Construct individual response data from contingency table
#
   for (i in 1 : Ncum[1, 1]) {
      group[i] <- 1
      for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }
   for (i in (Ncum[1,1] + 1) : Ncum[1, 2]) {
      group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }

   for (k in 2 : Npattern) {
      for(i in (Ncum[k - 1, 2] + 1) : Ncum[k, 1]) {
         group[i] <- 1 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
      for(i in (Ncum[k, 1] + 1) : Ncum[k, 2]) {
         group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
   }
#
# Model
#
   for (i in 1 : N) {
      for (t in 1 : T) {
         for (j in 1 : Ncut) {
#
# Cumulative probability of worse response than j
#
            logit(Q[i, t, j]) <- -(a[j] + mu[group[i], t] + b[i])
         }
#
# Probability of response = j
#
         p[i, t, 1] <- 1 - Q[i, t, 1]
         for (j in 2 : Ncut) { p[i, t, j] <- Q[i, t, j - 1] - Q[i, t, j] }
         p[i, t, (Ncut+1)] <- Q[i, t, Ncut]

         response[i, t] ~ dcat(p[i, t, ])
         cumulative.response[i, t] <- cumulative(response[i, t], response[i, t])
      }
#
# Subject (random) effects
#
      b[i] ~ dnorm(0.0, tau)
}

#
# Fixed effects
#
   for (g in 1 : G) {
      for(t in 1 : T) {
# logistic mean for group i in period t
         mu[g, t] <- beta * treat[g, t] / 2 + pi * period[g, t] / 2 + kappa * carry[g, t]
      }
   }
   beta ~ dnorm(0, 1.0E-06)
   pi ~ dnorm(0, 1.0E-06)
   kappa ~ dnorm(0, 1.0E-06)

# ordered cut points for underlying continuous latent variable
   a[1] ~ dflat()T(-1000, a[2])
   a[2] ~ dflat()T(a[1], a[3])
   a[3] ~ dflat()T(a[2], 1000)

   tau ~ dgamma(0.001, 0.001)
   sigma <- sqrt(1 / tau)
   log.sigma <- log(sigma)

}
"""
    )

    # pumps
    parse_bugs("""
    model
    {
       for (i in 1 : N) {
          theta[i] ~ dgamma(alpha, beta)
          lambda[i] <- theta[i] * t[i]
          x[i] ~ dpois(lambda[i])
       }
       alpha ~ dexp(1)
       beta ~ dgamma(0.1, 1.0)
    }""")

    # Dogs
    parse_bugs("""
    model
       {
          for (i in 1 : Dogs) {
             xa[i, 1] <- 0; xs[i, 1] <- 0 p[i, 1] <- 0
             for (j in 2 : Trials) {
                xa[i, j] <- sum(Y[i, 1 : j - 1])
                xs[i, j] <- j - 1 - xa[i, j]
                log(p[i, j]) <- alpha * xa[i, j] + beta * xs[i, j]
                y[i, j] <- 1 - Y[i, j]
                y[i, j] ~ dbern(p[i, j])
             }
          }
       alpha ~ dunif(-10, -0.00001)
       beta ~ dunif(-10, -0.00001)
       A <- exp(alpha)
       B <- exp(beta)
       }
    """)

    # seeds
    parse_bugs("""
    model
    {
       for( i in 1 : N ) {
          r[i] ~ dbin(p[i],n[i])
          beta[i] ~ dnorm(0.0,tau)
          logit(p[i]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
             alpha12 * x1[i] * x2[i] + beta[i]
       }
       alpha0 ~ dnorm(0.0,1.0E-6)
       alpha1 ~ dnorm(0.0,1.0E-6)
       alpha2 ~ dnorm(0.0,1.0E-6)
       alpha12 ~ dnorm(0.0,1.0E-6)
       sigma ~ dunif(0,10)
       tau <- 1 / pow(sigma, 2)
    }""")

    # surgical
    parse_bugs("""
    model
    {
       for( i in 1 : N ) {
          b[i] ~ dnorm(mu,tau)
          r[i] ~ dbin(p[i],n[i])
          logit(p[i]) <- b[i]
          }
       pop.mean <- exp(mu) / (1 + exp(mu))
       mu ~ dnorm(0.0,1.0E-6)
       sigma <- 1 / sqrt(tau)
       tau ~ dgamma(0.001,0.001)   
    }
    """)

    # Magnesium
    p = parse_bugs(
        """
    model
       {
       #   j indexes alternative prior distributions
          for (j in 1:6) {
             mu[j] ~ dunif(-10, 10)
             OR[j] <- exp(mu[j])
          
       #   k indexes study number
          for (k in 1:8) {
             theta[j, k] ~ dnorm(mu[j], inv.tau.sqrd[j])
             rtx[j, k] ~ dbin(pt[j, k], nt[k])
             rtx[j, k] <- rt[k]
             rcx[j, k] ~ dbin(pc[j, k], nc[k])
             rcx[j, k] <- rc[k]
             logit(pt[j, k]) <- theta[j, k] + phi[j, k]
             phi[j, k] <- logit(pc[j, k])
             pc[j, k] ~ dunif(0, 1)
          }
       }
          
       #   k again indexes study number
       for (k in 1:8) {
          # log-odds ratios:
          y[k] <- log(((rt[k] + 0.5) / (nt[k] - rt[k] + 0.5)) / ((rc[k] + 0.5) / (nc[k] - rc[k] + 0.5)))
    #    variances & precisions:
          sigma.sqrd[k] <- 1 / (rt[k] + 0.5) + 1 / (nt[k] - rt[k] + 0.5) + 1 / (rc[k] + 0.5) +
                   1 / (nc[k] - rc[k] + 0.5)
          prec.sqrd[k] <- 1 / sigma.sqrd[k]
       }
       s0.sqrd <- 1 / mean(prec.sqrd[1:8])
       # Prior 1: Gamma(0.001, 0.001) on inv.tau.sqrd

       inv.tau.sqrd[1] ~ dgamma(0.001, 0.001)
       tau.sqrd[1] <- 1 / inv.tau.sqrd[1]
       tau[1] <- sqrt(tau.sqrd[1])

    # Prior 2: Uniform(0, 50) on tau.sqrd

       tau.sqrd[2] ~ dunif(0, 50)
       tau[2] <- sqrt(tau.sqrd[2])
       inv.tau.sqrd[2] <- 1 / tau.sqrd[2]

    # Prior 3: Uniform(0, 50) on tau

       tau[3] ~ dunif(0, 50)
       tau.sqrd[3] <- tau[3] * tau[3]
       inv.tau.sqrd[3] <- 1 / tau.sqrd[3]

    # Prior 4: Uniform shrinkage on tau.sqrd

       B0 ~ dunif(0, 1)
       tau.sqrd[4] <- s0.sqrd * (1 - B0) / B0
       tau[4] <- sqrt(tau.sqrd[4])
       inv.tau.sqrd[4] <- 1 / tau.sqrd[4]

    # Prior 5: Dumouchel on tau

       D0 ~ dunif(0, 1)
       tau[5] <- sqrt(s0.sqrd) * (1 - D0) / D0
       tau.sqrd[5] <- tau[5] * tau[5]
       inv.tau.sqrd[5] <- 1 / tau.sqrd[5]

    # Prior 6: Half-Normal on tau.sqrd

       p0 <- phi(0.75) / s0.sqrd
       tau.sqrd[6] ~ dnorm(0, p0)T(0, )
       tau[6] <- sqrt(tau.sqrd[6])
       inv.tau.sqrd[6] <- 1 / tau.sqrd[6]
    }
    """,
    )

    # salm
    parse_bugs("""
    model
    {
       for( i in 1 : doses ) {
          for( j in 1 : plates ) {
             y[i , j] ~ dpois(mu[i , j])
             log(mu[i , j]) <- alpha + beta * log(x[i] + 10) +
                gamma * x[i] / 1000 + lambda[i , j]
             lambda[i , j] ~ dnorm(0.0, tau)   
          }
       }
       alpha ~ dnorm(0.0,1.0E-6)
       beta ~ dnorm(0.0,1.0E-6)
       gamma ~ dnorm(0.0,1.0E-6)
       tau ~ dgamma(0.001, 0.001)
       sigma <- 1 / sqrt(tau)
    }   
    """)

    # Equiv
    parse_bugs("""
    model
       {
          for( k in 1 : P ) {
             for( i in 1 : N ) {
                Y[i , k] ~ dnorm(m[i , k], tau1)
                m[i , k] <- mu + sign[T[i , k]] * phi / 2 + sign[k] * pi / 2 + delta[i]
                T[i , k] <- group[i] * (k - 1.5) + 1.5
             }
          }
          for( i in 1 : N ) {
             delta[i] ~ dnorm(0.0, tau2)
          }
          tau1 ~ dgamma(0.001, 0.001) sigma1 <- 1 / sqrt(tau1)
          tau2 ~ dgamma(0.001, 0.001) sigma2 <- 1 / sqrt(tau2)
          mu ~ dnorm(0.0, 1.0E-6)
          phi ~ dnorm(0.0, 1.0E-6)
          pi ~ dnorm(0.0, 1.0E-6)
          theta <- exp(phi)
          equiv <- step(theta - 0.8) - step(theta - 1.2)
       }
    """)

    # Dyes
    parse_bugs("""
    model
    {
       for(i in 1 : batches) {
          mu[i] ~ dnorm(theta, tau.btw)
          for(j in 1 : samples) {
             y[i , j] ~ dnorm(mu[i], tau.with)
          }
       }   
       sigma2.with <- 1 / tau.with
       sigma2.btw <- 1 / tau.btw
       tau.with ~ dgamma(0.001, 0.001)
       tau.btw ~ dgamma(0.001, 0.001)
       theta ~ dnorm(0.0, 1.0E-10)
    }
    """)

    # Stacks
    parse_bugs("""
    model
    {
    # Standardise x's and coefficients
       for (j in 1 : p) {
          b[j] <- beta[j] / sd(x[ , j ])
          for (i in 1 : N) {
             z[i, j] <- (x[i, j] - mean(x[, j])) / sd(x[ , j])
          }
       }
       b0 <- beta0 - b[1] * mean(x[, 1]) - b[2] * mean(x[, 2]) - b[3] * mean(x[, 3])

    # Model
       d <- 4; # degrees of freedom for t
    for (i in 1 : N) {
          Y[i] ~ dnorm(mu[i], tau)
    #      Y[i] ~ ddexp(mu[i], tau)
    #      Y[i] ~ dt(mu[i], tau, d)

          mu[i] <- beta0 + beta[1] * z[i, 1] + beta[2] * z[i, 2] + beta[3] * z[i, 3]
          stres[i] <- (Y[i] - mu[i]) / sigma
          outlier[i] <- step(stres[i] - 2.5) + step(-(stres[i] + 2.5) )
       }
    # Priors
       beta0 ~ dnorm(0, 0.00001)
       for (j in 1 : p) {
          beta[j] ~ dnorm(0, 0.00001)    # coeffs independent
    #      beta[j] ~ dnorm(0, phi) # coeffs exchangeable (ridge regression)
       }
       tau ~ dgamma(1.0E-3, 1.0E-3)
    #   phi ~ dgamma(1.0E-2,1.0E-2)
    # standard deviation of error distribution
       sigma <- sqrt(1 / tau) # normal errors
    #   sigma <- sqrt(2) / tau # double exponential errors
    #   sigma <- sqrt(d / (tau * (d - 2))); # t errors on d degrees of freedom
    }""")

    # Epil
    parse_bugs("""
    model
    {
       for(j in 1 : N) {
          for(k in 1 : T) {
             log(mu[j, k]) <- a0 + alpha.Base * (log.Base4[j] - log.Base4.bar)
    + alpha.Trt * (Trt[j] - Trt.bar)
    + alpha.BT * (BT[j] - BT.bar)
    + alpha.Age * (log.Age[j] - log.Age.bar)
    + alpha.V4 * (V4[k] - V4.bar)
    + b1[j] + b[j, k]
             y[j, k] ~ dpois(mu[j, k])
             b[j, k] ~ dnorm(0.0, tau.b); # subject*visit random effects
          }
          b1[j] ~ dnorm(0.0, tau.b1) # subject random effects
          BT[j] <- Trt[j] * log.Base4[j] # interaction
          log.Base4[j] <- log(Base[j] / 4) log.Age[j] <- log(Age[j])
       }
       
    # covariate means:
       log.Age.bar <- mean(log.Age[])
       Trt.bar <- mean(Trt[])
       BT.bar <- mean(BT[])
       log.Base4.bar <- mean(log.Base4[])
       V4.bar <- mean(V4[])
    # priors:

       a0 ~ dnorm(0.0,1.0E-4)       
       alpha.Base ~ dnorm(0.0,1.0E-4)
       alpha.Trt ~ dnorm(0.0,1.0E-4);
       alpha.BT ~ dnorm(0.0,1.0E-4)
       alpha.Age ~ dnorm(0.0,1.0E-4)
       alpha.V4 ~ dnorm(0.0,1.0E-4)
       tau.b1 ~ dgamma(1.0E-3,1.0E-3); sigma.b1 <- 1.0 / sqrt(tau.b1)
       tau.b ~ dgamma(1.0E-3,1.0E-3); sigma.b <- 1.0/ sqrt(tau.b)      
       
    # re-calculate intercept on original scale:
       alpha0 <- a0 - alpha.Base * log.Base4.bar - alpha.Trt * Trt.bar
       - alpha.BT * BT.bar - alpha.Age * log.Age.bar - alpha.V4 * V4.bar
    }
    """)

    # Blockers
    parse_bugs("""
    model
    {
    for( i in 1 : Num ) {
    rc[i] ~ dbin(pc[i], nc[i])
    rt[i] ~ dbin(pt[i], nt[i])
    logit(pc[i]) <- mu[i]
    logit(pt[i]) <- mu[i] + delta[i]
    mu[i] ~ dnorm(0.0,1.0E-5)
    delta[i] ~ dnorm(d, tau)
    }
    d ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    delta.new ~ dnorm(d, tau)
    sigma <- 1 / sqrt(tau)
    }
    """)

    # Oxford
    parse_bugs("""
    model
    {
       for (i in 1 : K) {
          r0[i] ~ dbin(p0[i], n0[i])
          r1[i] ~ dbin(p1[i], n1[i])
          logit(p0[i]) <- mu[i]
          logit(p1[i]) <- mu[i] + logPsi[i]
          logPsi[i] <- alpha + beta1 * year[i] + beta2 * (year[i] * year[i] - 22) + b[i]
          b[i] ~ dnorm(0, tau)
          mu[i] ~ dnorm(0.0, 1.0E-6)
       }
       alpha ~ dnorm(0.0, 1.0E-6)
       beta1 ~ dnorm(0.0, 1.0E-6)
       beta2 ~ dnorm(0.0, 1.0E-6)
       tau ~ dgamma(1.0E-3, 1.0E-3)
       sigma <- 1 / sqrt(tau)
    }
    """)

    # Lsat
    parse_bugs("""
    model
    {
    # Calculate individual (binary) responses to each test from multinomial data
       for (j in 1 : culm[1]) {
          for (k in 1 : T) {
             r[j, k] <- response[1, k]
          }
       }
       for (i in 2 : R) {
          for (j in culm[i - 1] + 1 : culm[i]) {
             for (k in 1 : T) {
                r[j, k] <- response[i, k]
             }
          }
       }
    # Rasch model
       for (j in 1 : N) {
          for (k in 1 : T) {
             logit(p[j, k]) <- beta * theta[j] - alpha[k]
             r[j, k] ~ dbern(p[j, k])
          }
          theta[j] ~ dnorm(0, 1)
       }
    # Priors
       for (k in 1 : T) {
          alpha[k] ~ dnorm(0, 0.0001)
          a[k] <- alpha[k] - mean(alpha[])
       }
       beta ~ dunif(0, 1000)
    }
    """)

    # Bones
    parse_bugs("""
    model
    {
       for (i in 1 : nChild) {
          theta[i] ~ dnorm(0.0, 0.001)
          for (j in 1 : nInd) {
    # Cumulative probability of > grade k given theta
             for (k in 1: ncat[j] - 1) {
                logit(Q[i, j, k]) <- delta[j] * (theta[i] - gamma[j, k])
             }
          }

    # Probability of observing grade k given theta
          for (j in 1 : nInd) {
             p[i, j, 1] <- 1 - Q[i, j, 1]
             for (k in 2 : ncat[j] - 1) {
                p[i, j, k] <- Q[i, j, k - 1] - Q[i, j, k]
             }
             p[i, j, ncat[j]] <- Q[i, j, ncat[j] - 1]
             grade[i, j] ~ dcat(p[i, j, 1 : ncat[j]])
          }
       }
    }
    """)

    # Inhaler
    parse_bugs(
        """
model
{
#
# Construct individual response data from contingency table
#
   for (i in 1 : Ncum[1, 1]) {
      group[i] <- 1
      for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }
   for (i in (Ncum[1,1] + 1) : Ncum[1, 2]) {
      group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[1, t] }
   }

   for (k in 2 : Npattern) {
      for(i in (Ncum[k - 1, 2] + 1) : Ncum[k, 1]) {
         group[i] <- 1 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
      for(i in (Ncum[k, 1] + 1) : Ncum[k, 2]) {
         group[i] <- 2 for (t in 1 : T) { response[i, t] <- pattern[k, t] }
      }
   }
#
# Model
#
   for (i in 1 : N) {
      for (t in 1 : T) {
         for (j in 1 : Ncut) {
#
# Cumulative probability of worse response than j
#
            logit(Q[i, t, j]) <- -(a[j] + mu[group[i], t] + b[i])
         }
#
# Probability of response = j
#
         p[i, t, 1] <- 1 - Q[i, t, 1]
         for (j in 2 : Ncut) { p[i, t, j] <- Q[i, t, j - 1] - Q[i, t, j] }
         p[i, t, (Ncut+1)] <- Q[i, t, Ncut]

         response[i, t] ~ dcat(p[i, t, ])
      }
#
# Subject (random) effects
#
      b[i] ~ dnorm(0.0, tau)
}

#
# Fixed effects
#
   for (g in 1 : G) {
      for(t in 1 : T) {
# logistic mean for group i in period t
         mu[g, t] <- beta * treat[g, t] / 2 + pi * period[g, t] / 2 + kappa * carry[g, t]
      }
   }
   beta ~ dnorm(0, 1.0E-06)
   pi ~ dnorm(0, 1.0E-06)
   kappa ~ dnorm(0, 1.0E-06)

# ordered cut points for underlying continuous latent variable
   a[1] ~ dunif(-1000, a[2])
   a[2] ~ dunif(a[1], a[3])
   a[3] ~ dunif(a[2], 1000)

   tau ~ dgamma(0.001, 0.001)
   sigma <- sqrt(1 / tau)
   log.sigma <- log(sigma)

}
"""
    )

    # Mice
    parse_bugs("""
    model
    {   
       for(i in 1 : M) {
          for(j in 1 : N) {
             t[i, j] ~ dweib(r, mu[i])C(t.cen[i, j],)
          }
          mu[i] <- exp(beta[i])
          beta[i] ~ dnorm(0.0, 0.001)
          median[i] <- pow(log(2) * exp(-beta[i]), 1/r)
       }
       #r ~ dexp(0.001)
       r ~ dunif(0.1, 10)
       veh.control <- beta[2] - beta[1]
       test.sub <- beta[3] - beta[1]
       pos.control <- beta[4] - beta[1]
    }
    """)

    # Kidney
    parse_bugs("""
    model
    {
       for (i in 1 : N) {
          for (j in 1 : M) {
    # Survival times bounded below by censoring times:
             t[i,j] ~ dweib(r, mu[i,j])C(t.cen[i, j], );
             log(mu[i,j ]) <- alpha + beta.age * age[i, j]
                   + beta.sex *sex[i]
                   + beta.dis[disease[i]] + b[i];
          }
    # Random effects:
          b[i] ~ dnorm(0.0, tau)
       }
    # Priors:
       alpha ~ dnorm(0.0, 0.0001);
       beta.age ~ dnorm(0.0, 0.0001);
       beta.sex ~ dnorm(0.0, 0.0001);
    #   beta.dis[1] <- 0; # corner-point constraint
       for(k in 2 : 4) {
          beta.dis[k] ~ dnorm(0.0, 0.0001);
       }
       tau ~ dgamma(1.0E-3, 1.0E-3);
       r ~ dgamma(1.0, 1.0E-3);
       sigma <- 1 / sqrt(tau); # s.d. of random effects
    }
    """)

    # Leuk
    parse_bugs("""
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
       c <- 0.001
       r <- 0.1
       for (j in 1 : T) {
          dL0.star[j] <- r * (t[j + 1] - t[j])
       }
       beta ~ dnorm(0.0,0.000001)
    }
    """)

    # LeukFr
    parse_bugs("""
    model
       {
       # Set up data
       for(i in 1 : N) {
          for(j in 1 : T) {
    # risk set = 1 if obs.t >= t
             Y[i, j] <- step(obs.t[i] - t[j] + eps)
    # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
    # i.e. if t[j] <= obs.t < t[j+1]
             dN[i, j] <- Y[i, j ] *step(t[j+1] - obs.t[i] - eps)*fail[i]
          }
          }
       # Model
          for(j in 1 : T) {
             for(i in 1 : N) {
                dN[i, j] ~ dpois(Idt[i, j])
                Idt[i, j] <- Y[i, j] * exp(beta * Z[i]+b[pair[i]]) * dL0[j]
             }
             dL0[j] ~ dgamma(mu[j], c)
             mu[j] <- dL0.star[j] * c # prior mean hazard
       # Survivor function = exp(-Integral{l0(u)du})^exp(beta * z)
             S.treat[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * -0.5))
             S.placebo[j] <- pow(exp(-sum(dL0[1 : j])), exp(beta * 0.5))   
          }
          for(k in 1 : Npairs) {
             b[k] ~ dnorm(0.0, tau);
          }
          tau ~ dgamma(0.001, 0.001)
          sigma <- sqrt(1 / tau)
          c <- 0.001 r <- 0.1
          for (j in 1 : T) {
             dL0.star[j] <- r * (t[j+1]-t[j])
          }
          beta ~ dnorm(0.0,0.000001)
       }
    """)

    ## Start Volume II

    # Dugongs
    parse_bugs("""
    model
    {
       for( i in 1 : N ) {
          Y[i] ~ dnorm(mu[i], tau)
          mu[i] <- alpha - beta * pow(gamma,x[i])   
       }
       alpha ~ dunif(0, 100)
       beta ~ dunif(0, 100)
       gamma ~ dunif(0.5, 1.0)
       tau ~ dgamma(0.001, 0.001)
       sigma <- 1 / sqrt(tau)
       U3 <- logit(gamma)   
    }
    """)

    # Orange Trees -- with `<--``
    parse_bugs("""
    model {
       for (i in 1:K) {
          for (j in 1:n) {
             Y[i, j] ~ dnorm(eta[i, j], tauC)
             eta[i, j] <- phi[i, 1] / (1 + phi[i, 2] * exp(phi[i, 3] * x[j]))
          }
          phi[i, 1] <- exp(theta[i, 1])
          phi[i, 2] <- exp(theta[i, 2]) - 1
          phi[i, 3] <--exp(theta[i, 3])
          for (k in 1:3) {
             theta[i, k] ~ dnorm(mu[k], tau[k])
          }
       }
       tauC ~ dgamma(1.0E-3, 1.0E-3)
       sigma.C <- 1 / sqrt(tauC)
       for (k in 1:3) {
          mu[k] ~ dnorm(0, 1.0E-4)
          tau[k] ~ dgamma(1.0E-3, 1.0E-3)
          sigma[k] <- 1 / sqrt(tau[k])
       }
    }
    """)

    # Orange Trees MVN
    parse_bugs("""
    model {
       for (i in 1:K) {
          for (j in 1:n) {
             Y[i, j] ~ dnorm(eta[i, j], tauC)
             eta[i, j] <- phi[i, 1] / (1 + phi[i, 2] * exp(phi[i, 3] * x[j]))
          }
          phi[i, 1] <- exp(theta[i, 1])
          phi[i, 2] <- exp(theta[i, 2]) - 1
          phi[i, 3] <- -exp(theta[i, 3])
          theta[i, 1:3] ~ dmnorm(mu[1:3], tau[1:3, 1:3])
       }
       mu[1:3] ~ dmnorm(mean[1:3], prec[1:3, 1:3])
       tau[1:3, 1:3] ~ dwish(R[1:3, 1:3], 3)
       sigma2[1:3, 1:3] <- inverse(tau[1:3, 1:3])
       for (i in 1 : 3) {sigma[i] <- sqrt(sigma2[i, i]) }
       tauC ~ dgamma(1.0E-3, 1.0E-3)
       sigmaC <- 1 / sqrt(tauC)
    }
    """)

    # Biopsies -- empty indices and `true` variable name 
    parse_bugs("""
     model
     {
        for (i in 1 : ns){
           nbiops[i] <- sum(biopsies[i, ])
           true[i] ~ dcat(p[])
           biopsies[i, 1 : 4] ~ dmulti(error[true[i], ], nbiops[i])
        }
        error[2,1 : 2] ~ ddirich(prior[1 : 2])
        error[3,1 : 3] ~ ddirich(prior[1 : 3])
        error[4,1 : 4] ~ ddirich(prior[1 : 4])
        p[1 : 4] ~ ddirich(prior[]); # prior for p
     }
     """)

    # eyes
    parse_bugs("""
    model
    {
       for( i in 1 : N ) {
          y[i] ~ dnorm(mu[i], tau)
          mu[i] <- lambda[T[i]]
          T[i] ~ dcat(P[])
       }   
       P[1:2] ~ ddirich(alpha[])
       theta ~ dunif(0.0, 1000)
       lambda[2] <- lambda[1] + theta
       lambda[1] ~ dnorm(0.0, 1.0E-6)
       tau ~ dgamma(0.001, 0.001) sigma <- 1 / sqrt(tau)
    }
    """)

    # hearts
    parse_bugs("""
    model
    {
       for (i in 1 : N) {
          y[i] ~ dbin(P[state1[i]], t[i])
          state[i] ~ dbern(theta)
          state1[i] <- state[i] + 1
          t[i] <- x[i] + y[i]
          prop[i] <- P[state1[i]]
       }
       P[1] <- p
       P[2] <- 0
       logit(p) <- alpha
       alpha ~ dnorm(0,1.0E-4)
       beta <- exp(alpha)
       logit(theta) <- delta
       delta ~ dnorm(0, 1.0E-4)
    }
    """)

    # Air
    parse_bugs("""
    model
    {
       for(j in 1 : J) {
          y[j] ~ dbin(p[j], n[j])
          logit(p[j]) <- theta[1] + theta[2] * X[j]
          X[j] ~ dnorm(mu[j], tau)
          mu[j] <- alpha + beta * Z[j]
       }
       theta[1] ~ dnorm(0.0, 0.001)
       theta[2] ~ dnorm(0.0, 0.001)
    }
    """)

    # Cervix
    parse_bugs("""
    model
    {
       for (i in 1 : N) {
          x[i] ~ dbern(q) # incidence of HSV
          logit(p[i]) <- beta0C + beta * x[i]   # logistic model
          d[i] ~ dbern(p[i]) # incidence of cancer
          x1[i] <- x[i] + 1
          d1[i] <- d[i] + 1
          w[i] ~ dbern(phi[x1[i], d1[i]])   # incidence of w
       }
       q ~ dunif(0.0, 1.0) # prior distributions
       beta0C ~ dnorm(0.0, 0.00001);
       beta ~ dnorm(0.0, 0.00001);
       for(j in 1 : 2) {
          for(k in 1 : 2){
                phi[j, k] ~ dunif(0.0, 1.0)
          }
       }
    # calculate gamma1 = P(x=1|d=0) and gamma2 = P(x=1|d=1)
       gamma1 <- 1 / (1 + (1 + exp(beta0C + beta)) / (1 + exp(beta0C)) * (1 - q) / q)
       gamma2 <- 1 / (1 + (1 + exp(-beta0C - beta)) / (1 + exp(-beta0C)) * (1 - q) / q)
       }
    """)

    # Jaws
    parse_bugs("""
    model
    {
    beta0 ~ dnorm(0.0, 0.001)
    beta1 ~ dnorm(0.0, 0.001)
    for (i in 1:N) {
       Y[i, 1:M] ~ dmnorm(mu[], Omega[ , ])
    }
    for(j in 1:M) {
       mu[j] <- beta0 + beta1* age[j]
    }
    Omega[1 : M , 1 : M] ~ dwish(R[ , ], 4)
    Sigma[1 : M , 1 : M] <- inverse(Omega[ , ])
       }
    """)

    # BiRats
    parse_bugs("""
    model
    {
    for( i in 1 : N ) {
    beta[i , 1 : 2] ~ dmnorm(mu.beta[], R[ , ])
    for( j in 1 : T ) {
    Y[i, j] ~ dnorm(mu[i , j], tauC)
    mu[i, j] <- beta[i, 1] + beta[i, 2] * x[j]
    }
    }

    mu.beta[1 : 2] ~ dmnorm(mean[], prec[ , ])
    R[1 : 2 , 1 : 2] ~ dwish(Omega[ , ], 2)
    tauC ~ dgamma(0.001, 0.001)
    sigma <- 1 / sqrt(tauC)
    }
    """)

    # Schools
    parse_bugs("""
    model
    {
       for(p in 1 : N) {
          Y[p] ~ dnorm(mu[p], tau[p])
          mu[p] <- alpha[school[p], 1] + alpha[school[p], 2] * LRT[p]
             + alpha[school[p], 3] * VR[p, 1] + beta[1] * LRT2[p]
             + beta[2] * VR[p, 2] + beta[3] * Gender[p]
             + beta[4] * School.gender[p, 1] + beta[5] * School.gender[p, 2]
             + beta[6] * School.denom[p, 1] + beta[7] * School.denom[p, 2]
             + beta[8] * School.denom[p, 3]
          log(tau[p]) <- theta + phi * LRT[p]
          sigma2[p] <- 1 / tau[p]
          LRT2[p] <- LRT[p] * LRT[p]
       }
       min.var <- exp(-(theta + phi * (-34.6193))) # lowest LRT score = -34.6193
       max.var <- exp(-(theta + phi * (37.3807))) # highest LRT score = 37.3807

    # Priors for fixed effects:
       for (k in 1 : 8) {
          beta[k] ~ dnorm(0.0, 0.0001)
       }
       theta ~ dnorm(0.0, 0.0001)
       phi ~ dnorm(0.0, 0.0001)

    # Priors for random coefficients:
       for (j in 1 : M) {
          alpha[j, 1 : 3] ~ dmnorm(gamma[1:3 ], T[1:3 ,1:3 ]);
          alpha1[j] <- alpha[j,1]
       }

    # Hyper-priors:
       gamma[1 : 3] ~ dmnorm(mn[1:3 ], prec[1:3 ,1:3 ]);
       T[1 : 3, 1 : 3 ] ~ dwish(R[1:3 ,1:3 ], 3)
    }
    """)

    # Ice
    parse_bugs(
        """
model
{
   for (i in 1:I) {
      cases[i] ~ dpois(mu[i])
      log(mu[i]) <- log(pyr[i]) + alpha[age[i]] + beta[year[i]]
   }
   betamean[1] <- 2 * beta[2] - beta[3]
   Nneighs[1] <- 1
   betamean[2] <- (2 * beta[1] + 4 * beta[3] - beta[4]) / 5
   Nneighs[2] <- 5
   for (k in 3 : K - 2) {
      betamean[k] <- (4 * beta[k - 1] + 4 * beta[k + 1]- beta[k - 2] - beta[k + 2]) / 6
      Nneighs[k] <- 6
   }
   betamean[K - 1] <- (2 * beta[K] + 4 * beta[K - 2] - beta[K - 3]) / 5
   Nneighs[K - 1] <- 5
   betamean[K] <- 2 * beta[K - 1] - beta[K - 2]
   Nneighs[K] <- 1
   for (k in 1 : K) {
      betaprec[k] <- Nneighs[k] * tau
   }
   for (k in 1 : K) {
      beta[k] ~ dnorm(betamean[k], betaprec[k])
      logRR[k] <- beta[k] - beta[5]
      tau.like[k] <- Nneighs[k] * beta[k] * (beta[k] - betamean[k])
   }
   alpha[1] <- 0.0
   for (j in 2 : Nage) {
      alpha[j] ~ dnorm(0, 1.0E-6)
   }
   d <- 0.0001 + sum(tau.like[]) / 2
   r <- 0.0001 + K / 2
   tau ~ dgamma(r, d)
   sigma <- 1 / sqrt(tau)
}
"""
    )

    # Beetles
    parse_bugs("""
    model
    {
    for( i in 1 : N ) {
    r[i] ~ dbin(p[i],n[i])
    logit(p[i]) <- alpha.star + beta * (x[i] - mean(x[]))
    rhat[i] <- n[i] * p[i]
    }
    alpha <- alpha.star - beta * mean(x[])
    beta ~ dnorm(0.0,0.001)
    alpha.star ~ dnorm(0.0,0.001)
    }
    """)

    # Alligators
    parse_bugs("""
    model
    {

    # PRIORS
       alpha[1] <- 0; # zero contrast for baseline food
       for (k in 2 : K) {
          alpha[k] ~ dnorm(0, 0.00001) # vague priors
       }
    # Loop around lakes:
       for (k in 1 : K){
          beta[1, k] <- 0
       } # corner-point contrast with first lake
       for (i in 2 : I) {
          beta[i, 1] <- 0 ; # zero contrast for baseline food
          for (k in 2 : K){
             beta[i, k] ~ dnorm(0, 0.00001) # vague priors
          }
       }
    # Loop around sizes:
       for (k in 1 : K){
          gamma[1, k] <- 0 # corner-point contrast with first size
       }
       for (j in 2 : J) {
          gamma[j, 1] <- 0 ; # zero contrast for baseline food
          for ( k in 2 : K){
             gamma[j, k] ~ dnorm(0, 0.00001) # vague priors
          }
       }

    # LIKELIHOOD   
       for (i in 1 : I) { # loop around lakes
          for (j in 1 : J) { # loop around sizes

    # Multinomial response
    # X[i,j,1 : K] ~ dmulti( p[i, j, 1 : K] , n[i, j] )
    # n[i, j] <- sum(X[i, j, ])
    # for (k in 1 : K) { # loop around foods
    # p[i, j, k] <- phi[i, j, k] / sum(phi[i, j, ])
    # log(phi[i ,j, k]) <- alpha[k] + beta[i, k] + gamma[j, k]
    # }

    # Fit standard Poisson regressions relative to baseline
                lambda[i, j] ~ dflat()   # vague priors
             for (k in 1 : K) { # loop around foods
                X[i, j, k] ~ dpois(mu[i, j, k])
                log(mu[i, j, k]) <- lambda[i, j] + alpha[k] + beta[i, k] + gamma[j, k]
                   cumulative.X[i, j, k] <- cdf.pois(X[i, j, k], mu[i, j, k])
             }
          }
       }

    # TRANSFORM OUTPUT TO ENABLE COMPARISON
    # WITH AGRESTI'S RESULTS

       for (k in 1 : K) { # loop around foods
          for (i in 1 : I) { # loop around lakes
             b[i, k] <- beta[i, k] - mean(beta[, k]); # sum to zero constraint
          }
          for (j in 1 : J) { # loop around sizes
             g[j, k] <- gamma[j, k] - mean(gamma[, k]); # sum to zero constraint
          }
       }
    }
    """)

    # Endo
    parse_bugs("""
    model
       {
       # transform collapsed data into full
          for (i in 1 : I){
             Y[i,1] <- 1
             Y[i,2] <- 0
          }
       # loop around strata with case exposed, control not exposed (n10)
          for (i in 1 : n10){
             est[i,1] <- 1
             est[i,2] <- 0
          }
       # loop around strata with case not exposed, control exposed (n01)
          for (i in (n10+1) : (n10+n01)){
             est[i,1] <- 0
             est[i,2] <- 1
          }
       # loop around strata with case exposed, control exposed (n11)
          for (i in (n10+n01+1) : (n10+n01+n11)){
             est[i,1] <- 1
             est[i,2] <- 1
          }
       # loop around strata with case not exposed, control not exposed (n00)
          for (i in (n10+n01+n11+1) :I ){
             est[i,1] <- 0
             est[i,2] <- 0
          }

       # PRIORS
          beta ~ dnorm(0,1.0E-6)
       
       # LIKELIHOOD
          for (i in 1 : I) { # loop around strata   
       # METHOD 1 - logistic regression
       # Y[i,1] ~ dbin( p[i,1], 1)
       # logit(p[i,1]) <- beta * (est[i,1] - est[i,J])
       # METHOD 2 - conditional likelihoods
             Y[i, 1 : J] ~ dmulti( p[i, 1 : J],1)
             for (j in 1:2){

                p[i, j] <- e[i, j] / sum(e[i, ])
                log( e[i, j] ) <- beta * est[i, j]
             }
       # METHOD 3 fit standard Poisson regressions relative to baseline
    #for (j in 1:J) {
    #   Y[i, j] ~ dpois(mu[i, j]);
    #   log(mu[i, j]) <- beta0[i] + beta*est[i, j];
       }
    #beta0[i] ~ dnorm(0, 1.0E-6)
       }
    """)

    # Stagnant
    parse_bugs("""
    model
    {
    for( i in 1 : N ) {
       Y[i] ~ dnorm(mu[i],tau)
       mu[i] <- alpha + beta[J[i]] * (x[i] - x[k])
       J[i] <- 1 + step(i - k - 0.5)
       punif[i] <- 1/N
    }
    tau ~ dgamma(0.001,0.001)
    alpha ~ dnorm(0.0,1.0E-6)
    for( j in 1 : 2 ) {
    beta[j] ~ dnorm(0.0,1.0E-6)
    }
    k ~ dcat(punif[])
    sigma <- 1 / sqrt(tau)
    }
    """)

    # Asia
    parse_bugs("""
    model{
    smoking ~ dcat(p.smoking[1:2])
    tuberculosis ~ dcat(p.tuberculosis[asia,1:2])
    lung.cancer ~ dcat(p.lung.cancer[smoking,1:2])
    bronchitis ~ dcat(p.bronchitis[smoking,1:2])
    either <- max(tuberculosis,lung.cancer)
    xray ~ dcat(p.xray[either,1:2])
    dyspnoea ~ dcat(p.dyspnoea[either,bronchitis,1:2])
    }
    """)

    # Pigs
    parse_bugs("""
    model
    {
    q ~ dunif(0,1) # prevalence of a1
    p <- 1 - q # prevalence of a2
    Ann1 ~ dbin(q,2); Ann <- Ann1 + 1 # geno. dist. for founder
    Brian1 ~ dbin(q,2); Brian <- Brian1 + 1
    Clare ~ dcat(p.mendelian[Ann,Brian,]) # geno. dist. for child
    Diane ~ dcat(p.mendelian[Ann,Brian,])
    Eric1 ~ dbin(q,2)
    Eric <- Eric1 + 1
    Fred ~ dcat(p.mendelian[Diane,Eric,])
    Gene ~ dcat(p.mendelian[Diane,Eric,])
    Henry1 ~ dbin(q,2)
    Henry <- Henry1 + 1
    Ian ~ dcat(p.mendelian[Clare,Fred,])
    Jane ~ dcat(p.mendelian[Gene,Henry,])
    A1 ~ dcat(p.recessive[Ann,]) # phenotype distribution
    B1 ~ dcat(p.recessive[Brian,])
    C1 ~ dcat(p.recessive[Clare,])
    D1 ~ dcat(p.recessive[Diane,])
    E1 ~ dcat(p.recessive[Eric,])
    F1 ~ dcat(p.recessive[Fred,])
    G1 ~ dcat(p.recessive[Gene,])
    H1 ~ dcat(p.recessive[Henry,])
    I1 ~ dcat(p.recessive[Ian,])
    J1 ~ dcat(p.recessive[Jane,])
    a <- equals(Ann, 2) # event that Ann is carrier
    b <- equals(Brian, 2)
    c <- equals(Clare, 2)
    d <- equals(Diane, 2)
    e <- equals(Eric, 2) ;
    f <- equals(Fred, 2)
    g <- equals(Gene, 2)
    h <- equals(Henry, 2)
    for (J in 1:3) {
    i[J] <- equals(Ian, J) # i[1] = a1 a1
    # i[2] = a1 a2
    # i[3] = a2 a2 (i.e. Ian affected)
    }    }
    """)

    # t-df
    parse_bugs("""
    model {
       for (i in 1:1000) {
          y[i] ~ dt(0, 1, d)
       }
       d ~ dunif(2, 100)         # degrees of freedom must be at least two
    }      """)
    #   test truncation
    parse_bugs("""model {
       for (i in 1:1000) {
          y[i] ~ dt(0, 1, d)T(-50, 50)
       }
       d ~ dunif(2, 100)         # degrees of freedom must be at least two
    }
    """)

    # Camel
    parse_bugs("""
    model
    {
       for (i in 1 : N){
          Y[i, 1 : 2] ~ dmnorm(mu[], tau[ , ])
       }
       mu[1] <- 0
       mu[2] <- 0
       tau[1 : 2,1 : 2] ~ dwish(R[ , ], 2)
       R[1, 1] <- 0.001
       R[1, 2] <- 0
       R[2, 1] <- 0;
       R[2, 2] <- 0.001
       Sigma2[1 : 2,1 : 2] <- inverse(tau[ , ])
       rho <- Sigma2[1, 2] / sqrt(Sigma2[1, 1] * Sigma2[2, 2])
    }
    """)

    # Eye Tracking
    parse_bugs("""
    model{   
       for( i in 1 : N ) {
          S[i] ~ dcat(pi[])
    mu[i] <- theta[S[i]]
    x[i] ~ dpois(mu[i])
          for (j in 1 : C) {
             SC[i, j] <- equals(j, S[i])
          }
       }
    # Precision Parameter
       alpha <- 1
    # alpha~ dgamma(0.1,0.1)
    # Constructive DPP
       p[1] <- r[1]
       for (j in 2 : C) {
          p[j] <- r[j] * (1 - r[j - 1]) * p[j -1 ] / r[j - 1]
       }
       p.sum <- sum(p[])
       for (j in 1:C){
          theta[j] ~ dgamma(A, B)
          r[j] ~ dbeta(1, alpha)
    # scaling to ensure sum to 1
          pi[j] <- p[j] / p.sum
       }
    # hierarchical prior on theta[i] or preset parameters
       A ~ dexp(0.1) B ~dgamma(0.1, 0.1)
    #   A <- 1 B <- 1
    # total clusters
       K <- sum(cl[])
       for (j in 1 : C) {
          sumSC[j] <- sum(SC[ , j])
          cl[j] <- step(sumSC[j] -1)
       }
    }
    """)

    # Fire -- this should error on pi < -3.14159565
    parse_bugs(
        """
    model{

    for ( i in 1 : N){

    dummy[i] <- 0
    dummy[i] ~ dloglik(logLike[i])
    logLike[i] <- log(r / phi(alpha * sigma)) * (1 - stepxtheta[i]) + log(1 - r) * stepxtheta[i] +
    (-0.5 * log(2 * pi) - log(x[i]) - log(sigma) - 0.5 * pow((log(x[i]) - mu )/ sigma, 2) ) *
    (1 - stepxtheta[i]) +
    (log(alpha) + alpha * log(theta) - (alpha + 1)* log(x[i])) * stepxtheta[i]

    stepxtheta[i] <- step(x[i] - theta)

    }

    theta ~ dgamma(0.001, 0.001) # dexp(0.5) #
    alpha ~ dgamma(0.001, 0.001) # dexp(0.5) #
    sigma ~ dgamma(0.001, 0.001) # dexp(0.5) #

    r <- (sqrt(2 *pi) * alpha * sigma * phi(alpha * sigma))
    / (sqrt(2 * pi) * alpha * sigma * phi(alpha * sigma) + exp(-0.5 * pow(alpha * sigma, 2)))
    mu <- log(theta) - alpha * pow(sigma, 2)
    pi <-3.14159565


    # xf prediction from fitted distribution
    xf <- xa * delta + xb * (1 - delta )
    xa ~ dlnorm(mu, tau )T( , theta )
    xb ~ dpar(alpha, theta)

    delta ~ dbern(r)
    tau <- 1 / pow(sigma, 2)

    }
    """,
    )

    # Hepatitis
    parse_bugs("""
    model
    {
    for( i in 1 : N ) {
    for( j in 1 : T ) {
    Y[i , j] ~ dnorm(mu[i , j],tau)
    mu[i , j] <- alpha[i] + beta[i] * (t[i,j] - 6.5) +
                               gamma * (y0[i] - mean(y0[]))
    }
    alpha[i] ~ dnorm(alpha0,tau.alpha)
    beta[i] ~ dnorm(beta0,tau.beta)
    }
    tau ~ dgamma(0.001,0.001)
    sigma <- 1 / sqrt(tau)
    alpha0 ~ dnorm(0.0,1.0E-6)   
    tau.alpha ~ dgamma(0.001,0.001)
    beta0 ~ dnorm(0.0,1.0E-6)
    tau.beta ~ dgamma(0.001,0.001)
    gamma ~ dnorm(0.0,1.0E-6)
    }
    """)

    # Hips model 1
    parse_bugs("""
    model {

    for(k in 1 : K) { # loop over strata

    # Cost and benefit equations in closed form:
    ####################################

    # Costs
    for(t in 1 : N) {
       ct[k, t] <- inprod(pi[k, t, ], c[]) / pow((1 + delta.c), t - 1)
    }
    C[k] <- C0 + sum(ct[k, ])

    # Benefits - life expectancy
    for(t in 1:N) {
       blt[k, t] <- inprod(pi[k, t, ], bl[]) / pow((1 + delta.b), t - 1)
    }
    BL[k] <- sum(blt[k, ])

    # Benefits - QALYs
    for(t in 1 : N) {
       bqt[k, t] <- inprod(pi[k,t, ], bq[]) / pow((1 + delta.b), t - 1)
    }
    BQ[k] <- sum(bqt[k, ])

    # Markov model probabilities:
    #######################

    # Transition matrix
    for(t in 2 : N) {
    Lambda[k, t, 1, 1] <- 1 - gamma[k, t] - lambda[k, t]
    Lambda[k, t, 1, 2] <- gamma[k, t] * lambda.op
    Lambda[k, t, 1, 3] <- gamma[k, t] * (1 - lambda.op)
    Lambda[k, t, 1, 4] <- 0
    Lambda[k, t, 1, 5] <- lambda[k, t]

    Lambda[k, t, 2, 1] <- 0
    Lambda[k, t, 2, 2] <- 0
    Lambda[k, t, 2, 3] <- 0
    Lambda[k, t, 2, 4] <- 0
    Lambda[k, t, 2, 5] <- 1

    Lambda[k, t, 3, 1] <- 0
    Lambda[k, t, 3, 2] <- 0
    Lambda[k, t, 3, 3] <- 0
    Lambda[k, t, 3, 4] <- 1 - lambda[k, t]
    Lambda[k, t, 3, 5] <- lambda[k, t]

    Lambda[k, t, 4, 1] <- 0
    Lambda[k, t, 4, 2] <- rho * lambda.op
    Lambda[k, t, 4, 3] <- rho * (1 - lambda.op)
    Lambda[k, t, 4, 4] <- 1 - rho - lambda[k, t]
    Lambda[k, t, 4, 5] <- lambda[k,t]

    Lambda[k, t, 5, 1] <- 0
    Lambda[k, t, 5, 2] <- 0
    Lambda[k, t, 5, 3] <- 0
    Lambda[k, t, 5, 4] <- 0
    Lambda[k, t, 5, 5] <- 1

    gamma[k, t] <- h[k] * (t - 1)
    }

    # Marginal probability of being in each state at time 1
    pi[k,1,1] <- 1 - lambda.op pi[k,1, 2]<-0 pi[k,1,3] <- 0
             pi[k,1, 4] <- 0 pi[k,1, 5] <- lambda.op

    # Marginal probability of being in each state at time t>1
    for(t in 2:N) {
       for(s in 1:S) {
          pi[k, t, s] <- inprod(pi[k, t - 1, ], Lambda[k, t, , s])
       }
       }

    }

    # Mean and sd of costs and benefits over strata
    #######################################

    mean.C <- inprod(p.strata[], C[])
    for(k in 1:12) {
             dev.C[k] <- pow(C[k] - mean.C, 2)
          }
    var.C <- inprod(p.strata[], dev.C[])
    sd.C <- sqrt(var.C)

    mean.BL <- inprod(p.strata[], BL[])
    for(k in 1:12) {
             dev.BL[k] <- pow(BL[k] - mean.BL, 2)
          }
    var.BL <- inprod(p.strata[], dev.BL[])
    sd.BL <- sqrt(var.BL)

    mean.BQ <- inprod(p.strata[], BQ[])
    for(k in 1:12) {
             dev.BQ[k] <- pow(BQ[k] - mean.BQ, 2)
          }
    var.BQ <- inprod(p.strata[], dev.BQ[])
    sd.BQ <- sqrt(var.BQ)
    }
    """)

    # Hips model 2
    parse_bugs("""
    model {

    for(k in 1 : K) { # loop over strata

    # Cost and benefit equations
    #######################

    # Costs
    for(t in 1 : N) {
       ct[k, t] <- inprod(y[k, t, ], c[]) / pow(1 + delta.c, t - 1)
    }
    C[k] <- C0 + sum(ct[k, ])

    # Benefits - life expectancy
    for(t in 1 : N) {
       blt[k, t] <- inprod(y[k, t, ], bl[]) / pow(1 + delta.b, t - 1)
    }
    BL[k] <- sum(blt[k, ])

    # Benefits - QALYs
    for(t in 1:N) {
       bqt[k, t] <- inprod(y[k, t, ], bq[]) / pow(1 + delta.b, t - 1)
    }
    BQ[k] <- sum(bqt[k, ])


    # Markov model probabilities:
    #######################

    # Transition matrix
    for(t in 1 : N) {
    Lambda[k, t, 1, 1] <- 1 - gamma[k, t] - lambda[k, t]
    Lambda[k, t, 1, 2] <- gamma[k, t] * lambda.op
    Lambda[k, t, 1, 3] <- gamma[k, t] *(1 - lambda.op)
    Lambda[k, t, 1, 4] <- 0
    Lambda[k, t, 1, 5] <- lambda[k, t]

    Lambda[k, t, 2, 1] <- 0
    Lambda[k, t, 2, 2] <- 0
    Lambda[k, t, 2, 3] <- 0
    Lambda[k, t, 2, 4] <- 0
    Lambda[k, t, 2, 5] <- 1

    Lambda[k, t, 3, 1] <- 0
    Lambda[k, t, 3, 2] <- 0
    Lambda[k, t, 3, 3] <- 0
    Lambda[k, t, 3, 4] <- 1 - lambda[k, t]
    Lambda[k, t, 3, 5] <- lambda[k, t]

    Lambda[k, t, 4, 1] <- 0
    Lambda[k, t, 4, 2] <- rho * lambda.op
    Lambda[k, t, 4, 3] <- rho * (1 - lambda.op)
    Lambda[k, t, 4, 4] <- 1 - rho - lambda[k, t]
    Lambda[k, t, 4, 5] <- lambda[k, t]

    Lambda[k, t, 5, 1] <- 0
    Lambda[k, t, 5, 2] <- 0
    Lambda[k, t, 5, 3] <- 0
    Lambda[k, t, 5, 4] <- 0
    Lambda[k, t, 5, 5] <- 1

    gamma[k, t] <- h[k] * (t - 1)
    }

    # Marginal probability of being in each state at time 1
    pi[k, 1, 1] <- 1 - lambda.op pi[k, 1, 2]<-0 pi[k, 1, 3] <- 0 pi[k, 1, 4] <- 0
          pi[k, 1, 5] <- lambda.op
    # state of each individual in strata k at time t =1
    y[k,1,1 : S] ~ dmulti(pi[k,1, ], 1)

    # state of each individual in strata k at time t > 1
    for(t in 2 : N) {
    for(s in 1:S) {
                   # sampling probabilities
       pi[k, t, s] <- inprod(y[k, t - 1, ], Lambda[k, t, , s])
       }
       y[k, t, 1 : S] ~ dmulti(pi[k, t, ], 1)
    }}

    # Mean of costs and benefits over strata
    #################################

    mean.C <- inprod(p.strata[], C[])
    mean.BL <- inprod(p.strata[], BL[])
    mean.BQ <- inprod(p.strata[], BQ[])

    }
    """)

    # Hips model 3
    parse_bugs("""
    model {

    for(k in 1 : K) { # loop over strata

    # Cost and benefit equations
    #######################

    # Costs
    for(t in 1 : N) {
       ct[k, t] <- inprod(pi[k, t, ], c[]) / pow(1 + delta.c, t - 1)
    }
    C[k] <- C0 + sum(ct[k, ])

    # Benefits - life expectancy
    for(t in 1 : N) {
       blt[k, t] <- inprod(pi[k, t, ], bl[]) / pow(1 + delta.b, t - 1)
    }
    BL[k] <- sum(blt[k, ])

    # Benefits - QALYs
    for(t in 1 : N) {
       bqt[k, t] <- inprod(pi[k, t, ], bq[]) / pow(1 + delta.b, t - 1)
    }
    BQ[k] <- sum(bqt[k, ])


    # Markov model probabilities:
    #######################

    # Transition matrix
    for(t in 2 : N) {
    Lambda[k, t, 1, 1] <- 1 - gamma[k, t] - lambda[k, t]
    Lambda[k, t, 1, 2] <- gamma[k, t] * lambda.op
    Lambda[k, t, 1, 3] <- gamma[k, t] *(1 - lambda.op)
    Lambda[k, t, 1, 4] <- 0
    Lambda[k, t, 1, 5] <- lambda[k, t]

    Lambda[k, t, 2, 1] <- 0
    Lambda[k, t, 2, 2] <- 0
    Lambda[k, t, 2, 3] <- 0
    Lambda[k, t, 2, 4] <- 0
    Lambda[k, t, 2, 5] <- 1

    Lambda[k, t, 3, 1] <- 0
    Lambda[k, t, 3, 2] <- 0
    Lambda[k,t,3,3] <- 0
    Lambda[k, t, 3, 4] <- 1 - lambda[k, t]
    Lambda[k, t, 3, 5] <- lambda[k, t]

    Lambda[k, t, 4, 1] <- 0
    Lambda[k, t, 4, 2] <- rho * lambda.op
    Lambda[k,t,4,3] <- rho * (1 - lambda.op)
    Lambda[k, t, 4, 4] <- 1 - rho - lambda[k, t]
    Lambda[k, t, 4, 5] <- lambda[k, t]

    Lambda[k, t, 5, 1] <- 0
    Lambda[k, t, 5, 2] <- 0
    Lambda[k, t, 5, 3] <- 0
    Lambda[k, t, 5, 4] <- 0
    Lambda[k, t, 5,5 ] <- 1

    gamma[k, t] <- h[k] * (t - 1)
    }

    # Marginal probability of being in each state at time 1
    pi[k,1,1] <- 1 - lambda.op pi[k,1, 2] <- 0 pi[k,1, 3] <- 0 ;
             pi[k,1, 4] <- 0 pi[k,1, 5] <- lambda.op

    # Marginal probability of being in each state at time t > 1
    for(t in 2 : N) {
    for(s in 1 : S) {
       pi[k, t, s] <- inprod(pi[k, t - 1, ], Lambda[k, t, , s])
    }
    }
    }

    # age-sex specific revision hazard
    for(k in 1 : K) {
    logh[k] ~ dnorm(logh0[k], tau)
    h[k] <- exp(logh[k])
    }

    # Calculate mean and variance across strata at each iteration
    # (Gives overall mean and variance using approach 1)

    mean.C <- inprod(p.strata[], C[])
    mean.BL <- inprod(p.strata[], BL[])
    mean.BQ <- inprod(p.strata[], BQ[])

    for(k in 1:12) {
    C.dev[k] <- pow(C[k]-mean.C , 2)
    BL.dev[k] <- pow(BL[k]-mean.BL , 2)
    BQ.dev[k] <- pow(BQ[k]-mean.BQ , 2)
       }
    var.C <- inprod(p.strata[], C.dev[])
    var.BL <- inprod(p.strata[], BL.dev[])
    var.BQ <- inprod(p.strata[], BQ.dev[])}
    """)

    # Hips model 4
    parse_bugs(
        """
    model {

    # Evidence
    #########

    for (i in 1 : M){ # loop over studies
    rC[i] ~ dbin(pC[i], nC[i]) # number of revisions on Charnley
    rS[i] ~ dbin(pS[i], nS[i]) # number of revisions on Stanmore
    cloglog(pC[i]) <- base[i] - logHR[i]/2
    cloglog(pS[i]) <- base[i] + logHR[i]/2
    base[i] ~ dunif(-100,100)
    # log hazard ratio for ith study
    logHR[i] ~ dnorm(LHR,tauHR[i])
    tauHR[i] <- qualweights[i] * tauh # precision for ith study weighted by quality weights
    }
    LHR ~ dunif(-100,100)
    log(HR) <- LHR
    tauh <- 1 / (sigmah * sigmah)
    sigmah ~ dnorm( 0.2, 400)T(0, ) # between-trial sd = 0.05 (prior constrained to be positive)

    for(k in 1 : K) {
    logh[k] ~ dnorm(logh0[k], tau)
    h[1, k] <- exp(logh[k]) # revision hazard for Charnley
    h[2, k] <- HR * h[1, k] # revision hazard for Stanmore
    }# Cost-effectiveness model
    ######################

    for(k in 1 : K) { # loop over strata

    for(n in 1 : 2) { # loop over protheses
    # Cost and benefit equations in closed form:
    ####################################

    # Costs
    for(t in 1 : N) {
       ct[n, k, t] <- inprod(pi[n, k, t, ], c[n, ]) / pow(1 + delta.c, t - 1)
    }
    C[n,k] <- C0[n] + sum(ct[n, k, ])

    # Benefits - life expectancy
    for(t in 1 : N) {
       blt[n, k, t] <- inprod(pi[n, k, t, ], bl[]) / pow(1 + delta.b, t - 1)
    }
    BL[n, k] <- sum(blt[n, k, ])

    # Benefits - QALYs
    for(t in 1 : N) {
       bqt[n, k, t] <- inprod(pi[n, k, t, ], bq[]) / pow(1 + delta.b, t - 1)
    }
    BQ[n, k] <- sum(bqt[n, k, ])

    # Markov model probabilities:
    #######################

    # Transition matrix
    for(t in 2:N) {
    Lambda[n, k, t, 1, 1] <- 1 - gamma[n, k, t] - lambda[k, t]
    Lambda[n, k, t, 1, 2] <- gamma[n, k, t] * lambda.op
    Lambda[n, k, t, 1, 3] <- gamma[n, k, t] *(1 - lambda.op)
    Lambda[n, k, t, 1, 4] <- 0
    Lambda[n, k, t, 1, 5] <- lambda[k, t]

    Lambda[n, k, t, 2, 1] <- 0
    Lambda[n, k, t, 2, 2] <- 0
    Lambda[n, k, t, 2, 3] <- 0
    Lambda[n, k, t, 2, 4] <- 0
    Lambda[n, k ,t, 2, 5] <- 1

    Lambda[n, k, t, 3, 1] <- 0
    Lambda[n, k, t, 3, 2] <- 0
    Lambda[n, k, t, 3, 3] <- 0
    Lambda[n, k, t, 3, 4] <- 1 - lambda[k, t]
    Lambda[n, k, t, 3, 5] <- lambda[k, t]

    Lambda[n, k, t, 4, 1] <- 0
    Lambda[n, k, t, 4, 2] <- rho * lambda.op
    Lambda[n, k, t, 4, 3] <- rho * (1 - lambda.op)
    Lambda[n, k, t, 4, 4] <- 1 - rho - lambda[k, t]
    Lambda[n, k, t, 4, 5] <- lambda[k, t]

    Lambda[n, k, t, 5, 1] <- 0
    Lambda[n, k, t, 5, 2] <- 0
    Lambda[n, k, t, 5, 3] <- 0
    Lambda[n, k, t, 5, 4] <- 0
    Lambda[n, k, t, 5, 5] <- 1

    gamma[n, k, t] <- h[n, k] * (t - 1)
       }

    # Marginal probability of being in each state at time 1
    pi[n, k, 1, 1] <- 1 - lambda.op pi[n, k, 1, 2] <- 0 pi[n, k, 1, 3] <- 0
             pi[n, k, 1, 4] <- 0 pi[n, k, 1, 5] <- lambda.op

    # Marginal probability of being in each state at time t>1
    for(t in 2 : N) {
    for(s in 1 : S) {
       pi[n, k,t, s] <- inprod(pi[n, k, t - 1, ], Lambda[n, k, t, , s])
    }
    }
    }
    }

    # Incremental costs and benefits
    ##########################

    for(k in 1 : K) {
    C.incr[k] <- C[2, k] - C[1, k]
    BQ.incr[k] <-BQ[2, k] - BQ[1, k]
    ICER.strata[k] <- C.incr[k] / BQ.incr[k]
    }

    # Probability of cost effectiveness @ KK pounds per QALY
    # (values of KK considered range from 200 to 20000 in 200 pound increments)
    for(m in 1 : 100) {
    for(k in 1 : 12) {
       P.CEA.strata[m,k] <- step(KK[m] * BQ.incr[k] - C.incr[k])
    }
       P.CEA[m] <- step(KK[m] * mean.BQ.incr - mean.C.incr)
    }

    # overall incremental costs and benefit
    for(n in 1 : 2) {
    mean.C[n] <- inprod(p.strata[], C[n, ])
    mean.BQ[n] <- inprod(p.strata[], BQ[n, ])
    }
    mean.C.incr <- mean.C[2] - mean.C[1]
    mean.BQ.incr <- mean.BQ[2] - mean.BQ[1]
    mean.ICER <- mean.C.incr / mean.BQ.incr }
       
       """,
    )

    # Jama River Valley Ecuador
    parse_bugs("""
    model{
          for (i in 1 : nDate){
             theta[i] ~ dunif(beta[phase[i]], alpha[phase[i]] )
             X[i] ~ dnorm(mu[i], tau[i])
             tau[i] <- 1 / pow(sigma[i], 2)
             mu[i] <- interp.lin(theta[i], calBP[], C14BP[])
          }
       # priors on phase ordering
          alpha[1] ~ dunif(beta[1], theta.max)
          beta[1] ~ dunif(alpha[2], alpha[1])
          alpha[2] ~ dunif(beta[2], beta[1])
          beta[2] ~ dunif(alpha[3], alpha[2])
          alpha[3] ~ dunif(beta[3], beta[2])
          beta[3] ~ dunif(alpha[4], alpha[3])
          alpha[4] ~ dunif(alpha4min, beta[3])
          alpha4min <- max(beta[4], alpha[5])
          beta[4] ~ dunif(beta[5], alpha[4])
          alpha[5] ~ dunif(alpha5min, alpha[4])
          alpha5min <- max(beta[5], alpha[6])
          beta[5] ~ dunif(beta[6], beta5max)
          beta5max <- min(beta[4], alpha[5])
          alpha[6] ~ dunif(beta[6], alpha[5])
          beta[6] ~ dunif(beta[7], beta6max)
          beta6max <- min(alpha[6], beta[5])
          alpha[7] <- beta[6]
          beta[7] ~ dunif(theta.min,alpha[7])
       
          for (i in 1 : 7) {
             alpha.desc[i] <- 10 * round(alpha[i] / 10)
             beta.desc[i] <- 10 * round(beta[i] / 10)
          }
       }
       """)

    # Pig Weight Gain
    parse_bugs("""
    model{
          y[1:s] ~ dmulti(th[1 : s] , n)
          sum.g <- sum(g[])
    # smoothed frequencies
       for (i in 1 : s) {
             Sm[i] <- n * th[i]
          g[i] <- exp(gam[i])
             th[i] <- g[i] / sum.g
          }
    # prior on elements of AR Precision Matrix
       rho ~ dunif(0, 1)
       tau ~ dunif(0.5, 10)
    # MVN for logit parameters
       gam[1 : s] ~ dmnorm(mu[], T[ , ])
       for (j in 1:s) {
             mu[j] <- -log(s)
          }
       # Define Precision Matrix
          for (j in 2 : s - 1) {
             T[j, j] <- tau * (1 + pow(rho, 2))
          }
          T[1, 1] <- tau
          T[s, s] <- tau
          for (j in 1 : s -1 ) {
             T[j, j + 1] <- -tau * rho
             T[j + 1, j] <- T[j, j + 1]
          }
          for (i in 1 : s - 1) {
             for (j in 2 + i : s) {
                T[i, j] <- 0; T[j, i] <- 0
             }
          }
    # Or Could do in terms of covariance, which is simpler to write but slower
    #      for (i in 1 : s) {
    #         for (j in 1 : s) {
    #            cov[i, j] <- pow(rho, abs(i - j)) / tau
    #         }
    #      }
    #      T[1 : s, 1 : s] <- inverse(cov[ , ])
       }
       """)

    # Pines
    parse_bugs("""
    model{
    # standardise data
    for(i in 1:N){
    Ys[i] <- (Y[i] - mean(Y[])) / sd(Y[])
    xs[i] <- (x[i] - mean(x[])) / sd(x[])
    zs[i] <- (z[i] - mean(z[])) / sd(z[])
    }

    # model node
    j ~ dcat(p[])
    p[1] <- 0.9995 p[2] <- 1 - p[1] # use for joint modelling
    # p[1] <- 1 p[2] <- 0 # include for estimating Model 1
    # p[1] <- 0 p[2] <-1 # include for estimating Model 2
    pM2 <- step(j - 1.5)

    # model structure
    for(i in 1 : N){
    mu[1, i] <- alpha + beta * xs[i]
    mu[2, i] <- gamma + delta*zs[i]
    Ys[i] ~ dnorm(mu[j, i], tau[j])
    }

    # Model 1
    alpha ~ dnorm(mu.alpha[j], tau.alpha[j])
    beta ~ dnorm(mu.beta[j], tau.beta[j])
    tau[1] ~ dgamma(r1[j], l1[j])
    # estimation priors
    mu.alpha[1]<- 0 tau.alpha[1] <- 1.0E-6
    mu.beta[1] <- 0 tau.beta[1] <- 1.0E-4
    r1[1] <- 0.0001 l1[1] <- 0.0001
    # pseudo-priors
    mu.alpha[2]<- 0 tau.alpha[2] <- 256
    mu.beta[2] <- 1 tau.beta[2] <- 256
    r1[2] <- 30 l1[2] <- 4.5

    # Model 2
    gamma ~ dnorm(mu.gamma[j], tau.gamma[j])
    delta ~ dnorm(mu.delta[j], tau.delta[j])
    tau[2] ~ dgamma(r2[j], l2[j])
    # pseudo-priors
    mu.gamma[1] <- 0 tau.gamma[1] <- 400
    mu.delta[1] <- 1 tau.delta[1] <- 400
    r2[1] <- 46 l2[1] <- 4.5
    # estimation priors
    mu.gamma[2] <- 0 tau.gamma[2] <- 1.0E-6
    mu.delta[2] <- 0 tau.delta[2] <- 1.0E-4
    r2[2] <- 0.0001 l2[2] <- 0.0001
    }
    """)

    # St Veit
    parse_bugs("""
    model{
       theta[1] ~ dunif(theta[2], theta.max)
       theta[2] ~ dunif(theta[3], theta[1])
       theta[3] ~ dunif(theta[9], theta[2])
       theta[4] ~ dunif(theta[9], theta.max)
       theta[5] ~ dunif(theta[7], theta.max)
       theta[6] ~ dunif(theta[7], theta.max)
       theta[7] ~ dunif(theta[9], theta7max)
       theta7max <- min(theta[5], theta[6])
       theta[8] ~ dunif(theta[9], theta.max)
       theta[9] ~ dunif(theta[10], theta9max)
       theta9max <-min(min(theta[3], theta[4]), min(theta[7], theta[8]))
       theta[10] ~ dunif(theta[11], theta[9])
       theta[11] ~ dunif(0 ,theta[10])
       
       bound[1] <- ranked(theta[1:8], 8)
       bound[2] <- ranked(theta[1:8], 1)
       bound[3] <- ranked(theta[9:11], 3)
       bound[4] <- ranked(theta[9:11], 1)
       
       for (j in 1 : 5){
          theta[j + 11] ~ dunif(0, theta.max)
          within[j, 1] <- 1 - step(bound[1] - theta[j + 11])
          for (k in 2 : 4){
             within[j, k] <- step(bound[k - 1] - theta[j + 11])
                   - step(bound[k] - theta[j + 11])
          }
          within[j, 5] <- step(bound[4] - theta[j + 11])
       }


       for (i in 1:nDate){
          X[i] ~ dnorm(mu[i], tau[i])
          tau[i] <- 1/pow(sigma[i],2)
          mu[i] <- interp.lin(theta[i], calBP[], C14BP[])

    # monitor the following variable to smooth density of theta
          theta.smooth[i] <- 10 * round(theta[i] / 10)
       }
    }
    """)

    # Start Volume IV

    # SeedsDataCloning
    parse_bugs("""
    model
    {
       for( i in 1 : N ) {
          for(k in 1 : K){   # replicate data and random effects
          r.rep[i, k] <- r[i]
          r.rep[i, k] ~ dbin(p[i, k],n[i])
          
          b[i, k] ~ dnorm(0.0,tau)
          logit(p[i, k]) <- alpha0 + alpha1 * x1[i] + alpha2 * x2[i] +
             alpha12 * x1[i] * x2[i] + b[i, k]
          }   
       }
       alpha0 ~ dnorm(0.0,1.0E-6)
       alpha1 ~ dnorm(0.0,1.0E-6)
       alpha2 ~ dnorm(0.0,1.0E-6)
       alpha12 ~ dnorm(0.0,1.0E-6)
       tau ~ dgamma(0.001,0.001)
       sigma <- 1 / sqrt(tau)
    }
    """)

    # coins
    parse_bugs("""
    model{
    p ~ dunif(0, 1)
    for (i in 1 : 10){
    r[i] ~ dbern(p)
    }
    r.total <- sum(r[]);
    valid <- equals(r.total, 6)
    p.valid <- p * valid
    p2.valid <- p * p * valid
    }
    """)

    # Smart phones
    parse_bugs("""
    model{
       N <- sum(r[])
       rNew[1 : 3] ~ dmulti(pHat[1 : 3] , N) # replicate data
       
       for(i in 1 : 3){
          pHat[i] <- r[i] / N # MLE for observed multinomal data
          p[i] <- rNew[i] / N # MLE for generated replicate multinomal data
       }
       iPhone <- step(p[1] - p[2]) # iPhone more popular than blackberry
    }
    """)

    # Abbey National
    parse_bugs("""
    model{
       for(i in 2 : N){
          z[i] ~ dstable(alpha, beta, gamma, delta)   
          z[i] <- price[i] / price[i - 1] - 1
       }
       
       alpha ~ dunif(1.1, 2)
       beta ~ dunif(-1, 1)
       gamma ~ dunif(-0.05, 0.05)
       delta ~ dunif(0.001, 0.5)
       
       mean.z <- mean(z[2:50])
       sd.z <- sd(z[2:50])
       z.pred ~ dstable(alpha, beta, gamma, delta)
    }
    """)

    # Beetles
    parse_bugs("""
    model
    {
       for(i in 1 : N) {
          for(j in 1 : r[i]) {
             y[i, j] ~ dnorm(mu[i], 1)C(0,)
          }
          for(j in r[i] + 1 : n[i]) {
             y[i, j] ~ dnorm(mu[i], 1)C(,0)
          }
          mu[i] <- alpha.star + beta * (x[i] - mean(x[]))
          rhat[i] <- n[i] * phi(mu[i])
       }
       alpha <- alpha.star - beta * mean(x[])
    beta ~ dnorm(0.0,0.001)
    alpha.star ~ dnorm(0.0,0.001)   
    }
    """)

    # Preeclampsia
    parse_bugs("""
    model {
       for (i in 1:N) {
       x.C[i] ~ dbin(pi.C[i], n.C[i])
       x.T[i] ~ dbin(pi.T[i], n.T[i])
       logit(pi.C[i]) <- eta[i] - theta[i]/2
       logit(pi.T[i]) <- eta[i] + theta[i]/2
       eta[i] ~ dnorm(0, 0.0001)
       theta[i] ~ dnorm(0, 0.0001)
       }
       }
    """)

    # Pollution
    parse_bugs("""
    model {

    #likelihood
       for(t in 1:T) {
          y[t] ~ dnorm(mu[t], tau.err)
          mu[t] <- beta + theta[t]
       }
                theta[1:T] ~ rand.walk(tau)
                #theta[1:T] ~ stoch.trend(tau)
    beta ~ dflat()
             # other priors
       tau.err ~ dgamma(0.01, 0.01)      # measurement error precision
       sigma.err <- 1 / sqrt(tau.err)
       sigma2.err <- 1/tau.err
       tau ~ dgamma(0.01, 0.01)            # random walk precision
       sigma <- 1 / sqrt(tau)
       sigma2 <- 1/tau
             # include this variable to use in time series (model fit) plot
       for(t in 1:T) { day[t] <- t }   
          }
    """)
end

@testset "Unsopported examples" begin
    # Lotka-Volterra
    # ! currently error, `D` function is not defined, probably won't impelment 
    @test_throws ParseError parse_bugs(
        """
    model
    {
    solution[1:ngrid, 1:ndim] <- ode.solution(init[1:ndim], tgrid[1:ngrid], D(C[1:ndim], t),
    origin, tol)

    alpha <- exp(log.alpha)
    beta <- exp(log.beta)
    gamma <- exp(log.gamma)
    delta <- exp(log.delta)
    log.alpha ~ dnorm(0.0, 0.0001)
    log.beta ~ dnorm(0.0, 0.0001)
    log.gamma ~ dnorm(0.0, 0.0001)
    log.delta ~ dnorm(0.0, 0.0001)

    D(C[1], t) <- C[1] * (alpha - beta * C[2])
    D(C[2], t) <- -C[2] * (gamma - delta * C[1])
        
    for (i in 1:ngrid)
    {
    sol_x[i] <- solution[i, 1]
    obs_x[i] ~ dnorm(sol_x[i], tau.x)
    sol_y[i] <- solution[i, 2]
    obs_y[i] ~ dnorm(sol_y[i], tau.y)
    }
        
    tau.x ~ dgamma(a, b)
    tau.y ~ dgamma(a, b)
    }
""",
    )

    # Five compartments
    # Change points
    # ! similarly, `D` function is not defined

    # Functionals
    # ! `F` is not defined
end
