name = "Hips4: Bayesian approaches to multiple sources of evidence and uncertainty in complex cost-effectiveness modelling"

model_def = @bugs begin
    # Evidence
    for i in 1:M  # loop over studies
        rC[i] ~ dbin(pC[i], nC[i])  # number of revisions on Charnley
        rS[i] ~ dbin(pS[i], nS[i])  # number of revisions on Stanmore
        cloglog(pC[i]) = base[i] - logHR[i] / 2
        cloglog(pS[i]) = base[i] + logHR[i] / 2
        base[i] ~ dunif(-100, 100)
        # log hazard ratio for ith study
        logHR[i] ~ dnorm(LHR, tauHR[i])
        tauHR[i] = qualweights[i] * tauh  # precision for ith study weighted by quality weights
    end
    LHR ~ dunif(-100, 100)
    log(HR) = LHR
    tauh = 1 / (sigmah * sigmah)
    sigmah ~ dnorm(0.2, 400)T(0,)  # between-trial sd = 0.05 (prior constrained to be positive)

    for k in 1:K
        logh[k] ~ dnorm(var"logh0"[k], tau)
        h[1, k] = exp(logh[k])  # revision hazard for Charnley
        h[2, k] = HR * h[1, k]  # revision hazard for Stanmore
    end

    # Cost-effectiveness model
    for k in 1:K  # loop over strata
        for n in 1:2  # loop over protheses
            # Cost and benefit equations in closed form:
            # Costs
            for t in 1:N
                ct[n, k, t] = inprod(pi[n, k, t, :], c[n, :]) / pow(1 + var"delta.c", t - 1)
            end
            C[n, k] = C0[n] + sum(ct[n, k, :])

            # Benefits - life expectancy
            for t in 1:N
                blt[n, k, t] = inprod(pi[n, k, t, :], bl[:]) / pow(1 + var"delta.b", t - 1)
            end
            BL[n, k] = sum(blt[n, k, :])

            # Benefits - QALYs
            for t in 1:N
                bqt[n, k, t] = inprod(pi[n, k, t, :], bq[:]) / pow(1 + var"delta.b", t - 1)
            end
            BQ[n, k] = sum(bqt[n, k, :])

            # Markov model probabilities:
            # Transition matrix
            for t in 2:N
                Lambda[n, k, t, 1, 1] = 1 - gamma[n, k, t] - lambda[k, t]
                Lambda[n, k, t, 1, 2] = gamma[n, k, t] * var"lambda.op"
                Lambda[n, k, t, 1, 3] = gamma[n, k, t] * (1 - var"lambda.op")
                Lambda[n, k, t, 1, 4] = 0
                Lambda[n, k, t, 1, 5] = lambda[k, t]

                Lambda[n, k, t, 2, 1] = 0
                Lambda[n, k, t, 2, 2] = 0
                Lambda[n, k, t, 2, 3] = 0
                Lambda[n, k, t, 2, 4] = 0
                Lambda[n, k, t, 2, 5] = 1

                Lambda[n, k, t, 3, 1] = 0
                Lambda[n, k, t, 3, 2] = 0
                Lambda[n, k, t, 3, 3] = 0
                Lambda[n, k, t, 3, 4] = 1 - lambda[k, t]
                Lambda[n, k, t, 3, 5] = lambda[k, t]

                Lambda[n, k, t, 4, 1] = 0
                Lambda[n, k, t, 4, 2] = rho * var"lambda.op"
                Lambda[n, k, t, 4, 3] = rho * (1 - var"lambda.op")
                Lambda[n, k, t, 4, 4] = 1 - rho - lambda[k, t]
                Lambda[n, k, t, 4, 5] = lambda[k, t]

                Lambda[n, k, t, 5, 1] = 0
                Lambda[n, k, t, 5, 2] = 0
                Lambda[n, k, t, 5, 3] = 0
                Lambda[n, k, t, 5, 4] = 0
                Lambda[n, k, t, 5, 5] = 1

                gamma[n, k, t] = h[n, k] * (t - 1)
            end

            # Marginal probability of being in each state at time 1
            pi[n, k, 1, 1] = 1 - var"lambda.op"
            pi[n, k, 1, 2] = 0
            pi[n, k, 1, 3] = 0
            pi[n, k, 1, 4] = 0
            pi[n, k, 1, 5] = var"lambda.op"

            # Marginal probability of being in each state at time t>1
            for t in 2:N
                for s in 1:S
                    pi[n, k, t, s] = inprod(pi[n, k, t - 1, :], Lambda[n, k, t, :, s])
                end
            end
        end
    end

    # Incremental costs and benefits
    for k in 1:K
        var"C.incr"[k] = C[2, k] - C[1, k]
        var"BQ.incr"[k] = BQ[2, k] - BQ[1, k]
        var"ICER.strata"[k] = var"C.incr"[k] / var"BQ.incr"[k]
    end

    # Probability of cost effectiveness @ KK pounds per QALY
    # (values of KK considered range from 200 to 20000 in 200 pound increments)
    for m in 1:100
        for k in 1:12
            var"P.CEA.strata"[m, k] = step(KK[m] * var"BQ.incr"[k] - var"C.incr"[k])
        end
        var"P.CEA"[m] = step(KK[m] * var"mean.BQ.incr" - var"mean.C.incr")
    end

    # overall incremental costs and benefit
    for n in 1:2
        var"mean.C"[n] = inprod(var"p.strata"[:], C[n, :])
        var"mean.BQ"[n] = inprod(var"p.strata"[:], BQ[n, :])
    end
    var"mean.C.incr" = var"mean.C"[2] - var"mean.C"[1]
    var"mean.BQ.incr" = var"mean.BQ"[2] - var"mean.BQ"[1]
    var"mean.ICER" = var"mean.C.incr" / var"mean.BQ.incr"
end

original = """
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
"""

data = (
    N = 60,                      # Number of cycles
    K = 12,                      # Number of age-sex strata
    S = 5,                       # Number of states in Markov model
    M = 3,                       # Number of studies in evidence synthesis
    rho = 0.04,                  # re-revision rate
    var"lambda.op" = 0.01,       # post-operative mortality rate
    # age-sex specific mean revision hazard for Charnley:
    var"logh0" = c(-6.119, -6.119, -6.119, -6.438, -6.438, -6.438,
        -6.377, -6.377, -6.377, -6.725, -6.725, -6.725),
    tau = 25,                    # inverse variance reflecting uncertainty about log revision hazard
    C0 = c(4052, 4402),          # set-up costs of primary operation
    # additional costs associated with each state and prothesis (zero except for revision states 2 and 3)
    c = [0 5290 5290 0 0; 0 5640 5640 0 0],
    bl = [1, 0, 1, 1, 0],        # life-expectancy benefits associated with each state (one except for death states 2 and 5)
    bq = [0.938, -0.622, -0.3387, 0.938, 0],    # QALYs associated with each state
    var"delta.c" = 0.06,         # cost discount
    var"delta.b" = 0.06,         # health discount
    # probablilty of hip replacement by age and sex
    var"p.strata" = [
        0.02, 0.03, 0.07, 0.13, 0.10, 0.00, 0.02, 0.04, 0.10, 0.22, 0.26, 0.01],
    lambda = [0.0017 0.0017 0.0017 0.0017 0.0017 0.0044 0.0044 0.0044 0.0044 0.0044 0.0044 0.0044 0.0044 0.0044 0.0044 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.0044 0.0044 0.0044 0.0044 0.0044 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0138 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.0138 0.0138 0.0138 0.0138 0.0138 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0379 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.0379 0.0379 0.0379 0.0379 0.0379 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.0912 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.0912 0.0912 0.0912 0.0912 0.0912 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958 0.1958;
              0.0011 0.0011 0.0011 0.0011 0.0011 0.0028 0.0028 0.0028 0.0028 0.0028 0.0028 0.0028 0.0028 0.0028 0.0028 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.0028 0.0028 0.0028 0.0028 0.0028 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.0081 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.0081 0.0081 0.0081 0.0081 0.0081 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.022 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.022 0.022 0.022 0.022 0.022 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503],
    # Amount health care provider is willing to pay for each additional QALY
    KK = [200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000,
        2200, 2400, 2600, 2800, 3000, 3200, 3400, 3600, 3800, 4000,
        4200, 4400, 4600, 4800, 5000, 5200, 5400, 5600, 5800, 6000,
        6200, 6400, 6600, 6800, 7000, 7200, 7400, 7600, 7800, 8000,
        8200, 8400, 8600, 8800, 9000, 9200, 9400, 9600,
        9800, 10000, 10200, 10400, 10600, 10800, 11000,
        11200, 11400, 11600, 11800, 12000, 12200, 12400, 12600,
        12800, 13000, 13200, 13400, 13600, 13800, 14000,
        14200, 14400, 14600, 14800, 15000, 15200, 15400, 15600,
        15800, 16000, 16200, 16400, 16600, 16800, 17000,
        17200, 17400, 17600, 17800, 18000, 18200, 18400, 18600,
        18800, 19000, 19200, 19400, 19600, 19800, 20000],
    # Evidence
    rC = [1683, 7, 33], # number of revisions for each study (Charnley)
    nC = [28525, 200, 208], # number of operations for each study (Charnley)
    rS = [28, 9, 69], # number of revisions for each study (Stanmore)
    nS = [865, 213, 982], # number of operations for each study (Stanmore)
    # Quality weights for each study
    qualweights = [0.5, 1, 0.2]    # qualweights = [0.1, 1, 0.05] # alternative quality weights for sensitivity analysis
)

inits = (
    base = [-3.09, -3.25, -2.12],
    logHR = [-0.63, 0.15, -0.92],
    LHR = -0.35
)

inits_alternative = (
    base = [0, 0, 0],
    logHR = [1, 1, 1],
    LHR = 1
)

reference_results = (
    var"BQ.incr[1]" = (mean = 0.1392, std = 0.0619),
    var"BQ.incr[2]" = (mean = 0.1154, std = 0.05106),
    var"BQ.incr[3]" = (mean = 0.08319, std = 0.03693),
    var"BQ.incr[4]" = (mean = 0.03889, std = 0.01744),
    var"BQ.incr[5]" = (mean = 0.02016, std = 0.009124),
    var"BQ.incr[6]" = (mean = 0.01352, std = 0.006099),
    var"BQ.incr[7]" = (mean = 0.1302, std = 0.0577),
    var"BQ.incr[8]" = (mean = 0.1118, std = 0.04939),
    var"BQ.incr[9]" = (mean = 0.08488, std = 0.03763),
    var"BQ.incr[10]" = (mean = 0.04113, std = 0.01848),
    var"BQ.incr[11]" = (mean = 0.02194, std = 0.009888),
    var"BQ.incr[12]" = (mean = 0.01536, std = 0.006892),
    var"C.incr[1]" = (mean = -105.0, std = 251.0),
    var"C.incr[2]" = (mean = -38.62, std = 209.2),
    var"C.incr[3]" = (mean = 62.14, std = 152.7),
    var"C.incr[4]" = (mean = 211.7, std = 72.68),
    var"C.incr[5]" = (mean = 277.4, std = 38.26),
    var"C.incr[6]" = (mean = 301.3, std = 25.61),
    var"C.incr[7]" = (mean = -75.88, std = 232.5),
    var"C.incr[8]" = (mean = -25.19, std = 201.1),
    var"C.incr[9]" = (mean = 57.93, std = 154.8),
    var"C.incr[10]" = (mean = 204.6, std = 76.55),
    var"C.incr[11]" = (mean = 271.5, std = 41.24),
    var"C.incr[12]" = (mean = 295.0, std = 28.76),
    var"HR" = (mean = 0.6054, std = 0.1584),
    var"ICER.strata[1]" = (mean = -9624.0, std = 1.346e6),
    var"ICER.strata[2]" = (mean = -9435.0, std = 1.399e6),
    var"ICER.strata[3]" = (mean = -10320.0, std = 1.703e6),
    var"ICER.strata[4]" = (mean = -16720.0, std = 3.395e6),
    var"ICER.strata[5]" = (mean = -41420.0, std = 8.35e6),
    var"ICER.strata[6]" = (mean = -18120.0, std = 6.573e6),
    var"ICER.strata[7]" = (mean = -9118.0, std = 1.306e6),
    var"ICER.strata[8]" = (mean = -9113.0, std = 1.36e6),
    var"ICER.strata[9]" = (mean = -10120.0, std = 1.655e6),
    var"ICER.strata[10]" = (mean = -11560.0, std = 2.555e6),
    var"ICER.strata[11]" = (mean = -19530.0, std = 5.045e6),
    var"ICER.strata[12]" = (mean = -12830.0, std = 5.1e6),
    var"P.CEA[30]" = (mean = 0.7457, std = 0.4354),
    var"P.CEA[50]" = (mean = 0.8662, std = 0.3404),
    var"P.CEA.strata[30,1]" = (mean = 0.9293, std = 0.2562),
    var"P.CEA.strata[30,2]" = (mean = 0.9197, std = 0.2717),
    var"P.CEA.strata[30,3]" = (mean = 0.8854, std = 0.3185),
    var"P.CEA.strata[30,4]" = (mean = 0.571, std = 0.4949),
    var"P.CEA.strata[30,5]" = (mean = 0.0392, std = 0.1941),
    var"P.CEA.strata[30,6]" = (mean = 0.00045, std = 0.02121),
    var"P.CEA.strata[30,7]" = (mean = 0.9258, std = 0.2621),
    var"P.CEA.strata[30,8]" = (mean = 0.9173, std = 0.2754),
    var"P.CEA.strata[30,9]" = (mean = 0.8892, std = 0.3139),
    var"P.CEA.strata[30,10]" = (mean = 0.6146, std = 0.4867),
    var"P.CEA.strata[30,11]" = (mean = 0.0718, std = 0.2582),
    var"P.CEA.strata[30,12]" = (mean = 0.0018, std = 0.04239),
    var"P.CEA.strata[50,1]" = (mean = 0.9491, std = 0.2198),
    var"P.CEA.strata[50,2]" = (mean = 0.944, std = 0.2298),
    var"P.CEA.strata[50,3]" = (mean = 0.9276, std = 0.2591),
    var"P.CEA.strata[50,4]" = (mean = 0.7882, std = 0.4086),
    var"P.CEA.strata[50,5]" = (mean = 0.2678, std = 0.4428),
    var"P.CEA.strata[50,6]" = (mean = 0.02395, std = 0.1529),
    var"P.CEA.strata[50,7]" = (mean = 0.9473, std = 0.2233),
    var"P.CEA.strata[50,8]" = (mean = 0.9429, std = 0.2319),
    var"P.CEA.strata[50,9]" = (mean = 0.929, std = 0.2567),
    var"P.CEA.strata[50,10]" = (mean = 0.8093, std = 0.3929),
    var"P.CEA.strata[50,11]" = (mean = 0.35, std = 0.477),
    var"P.CEA.strata[50,12]" = (mean = 0.06165, std = 0.2405)
)

hips4 = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
