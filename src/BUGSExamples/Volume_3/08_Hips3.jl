name = "Hips3: MC estimates for each strata, allowing for parameter uncertainty in revision hazard, h"

model_def = @bugs begin
    for k in 1:K
        # Cost and benefit equations in closed form:
        for t in 1:N
            ct[k, t] = inprod(var"pi"[k, t, :], c[:]) / pow((1 + var"delta.c"), t - 1)
        end
        C[k] = C0 + sum(ct[k, :])

        # Benefits - life expectancy
        for t in 1:N
            blt[k, t] = inprod(var"pi"[k, t, :], bl[:]) / pow((1 + var"delta.b"), t - 1)
        end
        BL[k] = sum(blt[k, :])

        # Benefits - QALYs
        for t in 1:N
            bqt[k, t] = inprod(var"pi"[k, t, :], bq[:]) / pow((1 + var"delta.b"), t - 1)
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

    # age-sex specific revision hazard
    for k in 1:K
        logh[k] ~ dnorm(var"logh0"[k], tau)
        h[k] = exp(logh[k])
    end

    # Calculate mean and variance across strata at each iteration 
    # (Gives overall mean and variance using approach 1)
    var"mean.C" = inprod(var"p.strata"[:], C[:])
    var"mean.BL" = inprod(var"p.strata"[:], BL[:])
    var"mean.BQ" = inprod(var"p.strata"[:], BQ[:])

    for k in 1:12
        var"C.dev"[k] = pow(C[k] - var"mean.C", 2)
        var"BL.dev"[k] = pow(BL[k] - var"mean.BL", 2)
        var"BQ.dev"[k] = pow(BQ[k] - var"mean.BQ", 2)
    end
    var"var.C" = inprod(var"p.strata"[:], var"C.dev"[:])
    var"var.BL" = inprod(var"p.strata"[:], var"BL.dev"[:])
    var"var.BQ" = inprod(var"p.strata"[:], var"BQ.dev"[:])
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
    var.BQ <- inprod(p.strata[], BQ.dev[])

}
"""

data = (
    N = 60,                      # Number of cycles
    K = 12,                      # Number of age-sex strata
    S = 5,                       # Number of states in Markov model
    rho = 0.04,                  # re-revision rate
    var"lambda.op" = 0.01,            # post-operative mortality rate
    # age-sex specific revision hazard:
    logh0 = [-6.119, -6.119, -6.119, -6.438, -6.438, -6.438,
        -6.377, -6.377, -6.377, -6.725, -6.725, -6.725],
    tau = 25,                       # inverse variance reflecting uncertainty about log revision hazard (= 1 / 0.2^2)
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

reference_results = (
    var"BL[1]" = (mean = 14.48, std = 0.005149),
    var"BL[2]" = (mean = 12.7, std = 0.003636),
    var"BL[3]" = (mean = 10.34, std = 0.002146),
    var"BL[4]" = (mean = 7.737, std = 0.0007918),
    var"BL[5]" = (mean = 5.405, std = 0.0003277),
    var"BL[6]" = (mean = 4.101, std = 0.0002131),
    var"BL[7]" = (mean = 15.13, std = 0.005099),
    var"BL[8]" = (mean = 13.69, std = 0.003885),
    var"BL[9]" = (mean = 11.65, std = 0.002426),
    var"BL[10]" = (mean = 9.1, std = 0.0009708),
    var"BL[11]" = (mean = 6.46, std = 0.0004248),
    var"BL[12]" = (mean = 4.988, std = 0.0002913),
    var"BQ[1]" = (mean = 13.17, std = 0.06006),
    var"BQ[2]" = (mean = 11.59, std = 0.05141),
    var"BQ[3]" = (mean = 9.468, std = 0.03856),
    var"BQ[4]" = (mean = 7.157, std = 0.01894),
    var"BQ[5]" = (mean = 5.018, std = 0.01004),
    var"BQ[6]" = (mean = 3.813, std = 0.006732),
    var"BQ[7]" = (mean = 13.82, std = 0.05649),
    var"BQ[8]" = (mean = 12.53, std = 0.0507),
    var"BQ[9]" = (mean = 10.69, std = 0.03913),
    var"BQ[10]" = (mean = 8.43, std = 0.02027),
    var"BQ[11]" = (mean = 6.004, std = 0.01089),
    var"BQ[12]" = (mean = 4.64, std = 0.007614),
    var"C[1]" = (mean = 5790.0, std = 230.0),
    var"C[2]" = (mean = 5427.0, std = 199.9),
    var"C[3]" = (mean = 4999.0, std = 152.2),
    var"C[4]" = (mean = 4471.0, std = 75.77),
    var"C[5]" = (mean = 4267.0, std = 40.55),
    var"C[6]" = (mean = 4195.0, std = 27.21),
    var"C[7]" = (mean = 5634.0, std = 215.4),
    var"C[8]" = (mean = 5362.0, std = 196.0),
    var"C[9]" = (mean = 5007.0, std = 153.5),
    var"C[10]" = (mean = 4494.0, std = 80.64),
    var"C[11]" = (mean = 4285.0, std = 43.69),
    var"C[12]" = (mean = 4215.0, std = 30.57),
    var"mean.BL" = (mean = 8.687, std = 0.0004563),
    var"mean.BQ" = (mean = 8.015, std = 0.008174),
    var"mean.C" = (mean = 4609.0, std = 32.31),
    var"var.BL" = (mean = 6.714, std = 0.003008),
    var"var.BQ" = (mean = 5.466, std = 0.03841),
    var"var.C" = (mean = 174500.0, std = 28450.0)
)

hips3 = Example(
    name, model_def, original, data, NamedTuple(), NamedTuple(), reference_results)
