name = "Hips1: Closed form estimates for each strata"

# there are no stochastic variables in this model

model_def = @bugs begin
    for k in 1:K
        # Cost and benefit equations in closed form:
        for t in 1:N
            ct[k, t] = inprod(pi[k, t, :], c[:]) / pow((1 + var"delta.c"), t - 1)
        end
        C[k] = C0 + sum(ct[k, :])

        # Benefits - life expectancy
        for t in 1:N
            blt[k, t] = inprod(pi[k, t, :], bl[:]) / pow((1 + var"delta.b"), t - 1)
        end
        BL[k] = sum(blt[k, :])

        # Benefits - QALYs
        for t in 1:N
            bqt[k, t] = inprod(pi[k, t, :], bq[:]) / pow((1 + var"delta.b"), t - 1)
        end
        BQ[k] = sum(bqt[k, :])

        # Markov model probabilities:
        # Transition matrix
        for t in 2:N
            Lambda[k, t, 1, 1] = 1 - gamma[k, t] - lambda[k, t]
            Lambda[k, t, 1, 2] = gamma[k, t] * var"lambda.op"
            Lambda[k, t, 1, 3] = gamma[k, t] * (1 - var"lambda.op")
            Lambda[k, t, 1, 4] = 0
            Lambda[k, t, 1, 5] = lambda[k, t]

            Lambda[k, t, 2, 1] = 0
            Lambda[k, t, 2, 2] = 0
            Lambda[k, t, 2, 3] = 0
            Lambda[k, t, 2, 4] = 0
            Lambda[k, t, 2, 5] = 1

            Lambda[k, t, 3, 1] = 0
            Lambda[k, t, 3, 2] = 0
            Lambda[k, t, 3, 3] = 0
            Lambda[k, t, 3, 4] = 1 - lambda[k, t]
            Lambda[k, t, 3, 5] = lambda[k, t]

            Lambda[k, t, 4, 1] = 0
            Lambda[k, t, 4, 2] = rho * var"lambda.op"
            Lambda[k, t, 4, 3] = rho * (1 - var"lambda.op")
            Lambda[k, t, 4, 4] = 1 - rho - lambda[k, t]
            Lambda[k, t, 4, 5] = lambda[k, t]

            Lambda[k, t, 5, 1] = 0
            Lambda[k, t, 5, 2] = 0
            Lambda[k, t, 5, 3] = 0
            Lambda[k, t, 5, 4] = 0
            Lambda[k, t, 5, 5] = 1

            gamma[k, t] = h[k] * (t - 1)
        end

        # Marginal probability of being in each state at time 1
        var"pi"[k, 1, 1] = 1 - var"lambda.op"
        var"pi"[k, 1, 2] = 0
        var"pi"[k, 1, 3] = 0
        var"pi"[k, 1, 4] = 0
        var"pi"[k, 1, 5] = var"lambda.op"

        # Marginal probability of being in each state at time t>1
        for t in 2:N
            for s in 1:S
                var"pi"[k, t, s] = inprod(var"pi"[k, t - 1, :], Lambda[k, t, :, s])
            end
        end
    end

    # Mean and sd of costs and benefits over strata
    var"mean.C" = inprod(var"p.strata"[:], C[:])
    for k in 1:12
        var"dev.C"[k] = pow(C[k] - var"mean.C", 2)
    end
    var"var.C" = inprod(var"p.strata"[:], var"dev.C"[:])
    var"sd.C" = sqrt(var"var.C")

    var"mean.BL" = inprod(var"p.strata"[:], BL[:])
    for k in 1:12
        var"dev.BL"[k] = pow(BL[k] - var"mean.BL", 2)
    end
    var"var.BL" = inprod(var"p.strata"[:], var"dev.BL"[:])
    var"sd.BL" = sqrt(var"var.BL")

    var"mean.BQ" = inprod(var"p.strata"[:], BQ[:])
    for k in 1:12
        var"dev.BQ"[k] = pow(BQ[k] - var"mean.BQ", 2)
    end
    var"var.BQ" = inprod(var"p.strata"[:], var"dev.BQ"[:])
    var"sd.BQ" = sqrt(var"var.BQ")
end

original = """
model {
    for(k in 1 : K) {    # loop over strata

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
            Lambda[k, t, 1, 1] <- 1 -  gamma[k, t] - lambda[k, t]
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
            Lambda[k, t, 3, 4] <- 1 -  lambda[k, t]
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
        pi[k,1,1] <- 1 - lambda.op  pi[k,1, 2]<-0     pi[k,1,3] <- 0   
        pi[k,1, 4] <- 0   pi[k,1, 5] <- lambda.op

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
        dev.C[k]  <- pow(C[k] - mean.C, 2) 
    }
    var.C <- inprod(p.strata[], dev.C[])
    sd.C <- sqrt(var.C)

    mean.BL <- inprod(p.strata[], BL[])
    for(k in 1:12) { 
        dev.BL[k]  <- pow(BL[k] - mean.BL, 2) 
    }
    var.BL <- inprod(p.strata[], dev.BL[])
    sd.BL <- sqrt(var.BL)

    mean.BQ <- inprod(p.strata[], BQ[])
    for(k in 1:12) { 
        dev.BQ[k]  <- pow(BQ[k] - mean.BQ, 2) 
    }
    var.BQ <- inprod(p.strata[], dev.BQ[])
    sd.BQ <- sqrt(var.BQ)
}
"""

data = (
    N = 60,                      # Number of cycles
    K = 12,                      # Number of age-sex strata
    S = 5,                       # Number of states in Markov model
    rho = 0.04,                  # re-revision rate
    var"lambda.op" = 0.01,            # post-operative mortality rate
    # age-sex specific revision hazard:
    h = [0.0022, 0.0022, 0.0022, 0.0016, 0.0016, 0.0016,
        0.0017, 0.0017, 0.0017, 0.0012, 0.0012, 0.0012],
    C0 = 4052,                   # set-up costs of primary operation
    c = [0, 5290, 5290, 0, 0],   # additional costs associated with each state (zero except for revision states 2 and 3) 
    bl = [1, 0, 1, 1, 0],        # life-expectancy benefits associated with each state (one except for death states 2 and 5)
    bq = [0.938, -0.622, -0.3387, 0.938, 0],    # QALYs associated with each state
    var"delta.c" = 0.06,              # cost discount
    var"delta.b" = 0.06,              # health discount
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
              0.022 0.022 0.022 0.022 0.022 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.0578 0.0578 0.0578 0.0578 0.0578 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503;
              0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503 0.1503]
)

reference_results = NamedTuple()

hips1 = Example(
    name, model_def, original, data, NamedTuple(), NamedTuple(), reference_results)
