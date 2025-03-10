name = "Hips2: MC estimates for each strata"

model_def = @bugs begin
    for k in 1:K
        # Cost and benefit equations
        for t in 1:N
            ct[k, t] = inprod(y[k, t, :], c[:]) / pow((1 + var"delta.c"), t - 1)
        end
        C[k] = C0 + sum(ct[k, :])

        # Benefits - life expectancy
        for t in 1:N
            blt[k, t] = inprod(y[k, t, :], bl[:]) / pow((1 + var"delta.b"), t - 1)
        end
        BL[k] = sum(blt[k, :])

        # Benefits - QALYs
        for t in 1:N
            bqt[k, t] = inprod(y[k, t, :], bq[:]) / pow((1 + var"delta.b"), t - 1)
        end
        BQ[k] = sum(bqt[k, :])

        # Markov model probabilities:
        # Transition matrix
        for t in 1:N
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
        pi[k, 1, 1] = 1 - var"lambda.op"
        pi[k, 1, 2] = 0
        pi[k, 1, 3] = 0
        pi[k, 1, 4] = 0
        pi[k, 1, 5] = var"lambda.op"

        # state of each individual in strata k at time t=1
        y[k, 1, :] ~ dmulti(pi[k, 1, :], 1)

        # state of each individual in strata k at time t > 1
        for t in 2:N
            for s in 1:S
                # sampling probabilities
                pi[k, t, s] = inprod(y[k, t - 1, :], Lambda[k, t, :, s])
            end
            y[k, t, :] ~ dmulti(pi[k, t, :], 1)
        end
    end

    # Mean of costs and benefits over strata
    var"mean.C" = inprod(var"p.strata"[:], C[:])
    var"mean.BL" = inprod(var"p.strata"[:], BL[:])
    var"mean.BQ" = inprod(var"p.strata"[:], BQ[:])
end

original = """
model {

		for(k in 1 : K) {    # loop over strata

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
				Lambda[k, t, 1, 1] <- 1 -  gamma[k, t] - lambda[k, t]
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
				Lambda[k, t, 3, 4] <- 1 -  lambda[k, t]
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
			pi[k, 1, 1] <- 1 - lambda.op  pi[k, 1, 2]<-0     pi[k, 1, 3] <- 0   pi[k, 1, 4] <- 0  
			pi[k, 1, 5] <- lambda.op

			# state of each individual in strata k at time t =1 
			y[k,1,1 : S] ~ dmulti(pi[k,1, ], 1)   

			# state of each individual in strata k at time t > 1
			for(t in 2 : N) {
				for(s in 1:S) {                 
					#  sampling probabilities        
					pi[k, t, s] <- inprod(y[k, t - 1, ], Lambda[k, t, , s])   
				}
				y[k, t, 1 : S] ~ dmulti(pi[k, t, ], 1)     
			}

		}

		# Mean of costs and benefits over strata
		#################################

		mean.C <- inprod(p.strata[], C[])
		mean.BL <- inprod(p.strata[], BL[])
		mean.BQ <- inprod(p.strata[], BQ[])

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

reference_results = (
    var"BL[1]" = (mean = 14.46, std = 2.893),
    var"BL[2]" = (mean = 12.72, std = 3.326),
    var"BL[3]" = (mean = 10.34, std = 3.68),
    var"BL[4]" = (mean = 7.74, std = 3.544),
    var"BL[5]" = (mean = 5.38, std = 2.988),
    var"BL[6]" = (mean = 4.093, std = 2.922),
    var"BL[7]" = (mean = 15.13, std = 2.649),
    var"BL[8]" = (mean = 13.72, std = 3.105),
    var"BL[9]" = (mean = 11.69, std = 3.507),
    var"BL[10]" = (mean = 9.117, std = 3.641),
    var"BL[11]" = (mean = 6.453, std = 3.316),
    var"BL[12]" = (mean = 4.988, std = 3.46),
    var"BQ[1]" = (mean = 13.15, std = 2.632),
    var"BQ[2]" = (mean = 11.6, std = 3.012),
    var"BQ[3]" = (mean = 9.469, std = 3.338),
    var"BQ[4]" = (mean = 7.16, std = 3.255),
    var"BQ[5]" = (mean = 4.999, std = 2.757),
    var"BQ[6]" = (mean = 3.805, std = 2.698),
    var"BQ[7]" = (mean = 13.81, std = 2.426),
    var"BQ[8]" = (mean = 12.55, std = 2.831),
    var"BQ[9]" = (mean = 10.74, std = 3.197),
    var"BQ[10]" = (mean = 8.445, std = 3.349),
    var"BQ[11]" = (mean = 5.996, std = 3.057),
    var"BQ[12]" = (mean = 4.642, std = 3.2),
    var"C[1]" = (mean = 5788.0, std = 1908.0),
    var"C[2]" = (mean = 5422.0, std = 1875.0),
    var"C[3]" = (mean = 5001.0, std = 1705.0),
    var"C[4]" = (mean = 4470.0, std = 1235.0),
    var"C[5]" = (mean = 4251.0, std = 898.6),
    var"C[6]" = (mean = 4192.0, std = 769.6),
    var"C[7]" = (mean = 5623.0, std = 1795.0),
    var"C[8]" = (mean = 5353.0, std = 1781.0),
    var"C[9]" = (mean = 4986.0, std = 1615.0),
    var"C[10]" = (mean = 4497.0, std = 1268.0),
    var"C[11]" = (mean = 4292.0, std = 977.8),
    var"C[12]" = (mean = 4207.0, std = 783.4),
    var"mean.BL" = (mean = 8.692, std = 1.369),
    var"mean.BQ" = (mean = 8.02, std = 1.258),
    var"mean.C" = (mean = 4607.0, std = 479.8)
)

hips2 = Example(name, model_def, original, data, nothing, nothing, reference_results)
