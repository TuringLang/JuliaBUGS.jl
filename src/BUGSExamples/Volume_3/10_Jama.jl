name = "Jama: Radiocarbon calibration with phase information"

model_def = @bugs begin
    for i in 1:nDate
        theta[i] ~ dunif(beta[phase[i]], alpha[phase[i]])
        X[i] ~ dnorm(mu[i], tau[i])
        tau[i] = 1 / pow(sigma[i], 2)
        mu[i] = interp.lin(theta[i], calBP[:], C14BP[:])
    end
    # priors on phase ordering
    alpha[1] ~ dunif(beta[1], theta.max)
    beta[1] ~ dunif(alpha[2], alpha[1])
    alpha[2] ~ dunif(beta[2], beta[1])
    beta[2] ~ dunif(alpha[3], alpha[2])
    alpha[3] ~ dunif(beta[3], beta[2])
    beta[3] ~ dunif(alpha[4], alpha[3])
    alpha[4] ~ dunif(alpha4min, beta[3])
    alpha4min = max(beta[4], alpha[5])
    beta[4] ~ dunif(beta[5], alpha[4])
    alpha[5] ~ dunif(alpha5min, alpha[4])
    alpha5min = max(beta[5], alpha[6])
    beta[5] ~ dunif(beta[6], beta5max)
    beta5max = min(beta[4], alpha[5])
    alpha[6] ~ dunif(beta[6], alpha[5])
    beta[6] ~ dunif(beta[7], beta6max)
    beta6max = min(alpha[6], beta[5])
    alpha[7] = beta[6]
    beta[7] ~ dunif(theta.min, alpha[7])
    for i in 1:7
        alpha.desc[i] = 10 * round(alpha[i] / 10)
        beta.desc[i] = 10 * round(beta[i] / 10)
    end
end

original = """
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
   beta[2] ~ dunif(alpha[3], alpha[2])
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
"""

# Data from the example
data = (
    nDate = 37,
    theta.max = 10000,
    theta.min = 0,
    X = [3630, 3620, 3560, 3545, 3500, 3030, 2845, 2800, 2500, 2430, 2170, 2125, 1990,
        1980, 1960, 1950, 1610, 1590, 1540, 1520, 1480, 1330, 1260, 1240, 1195, 1170,
        1120, 1120, 1030, 960, 880, 870, 820, 800, 630, 515, 305],
    sigma = [70, 70, 70, 135, 70, 80, 95, 115, 160, 170, 40, 300, 100, 70, 90, 70, 70,
        80, 70, 80, 75, 70, 30, 40, 85, 340, 30, 90, 90, 35, 70, 45, 70, 40, 30, 40, 35],
    phase = [1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5,
        5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 7],
    # Note: calBP and C14BP arrays are not provided in the example data
    # These would need to be filled with appropriate calibration data
    calBP = [0], # Placeholder - needs actual calibration data
    C14BP = [0]  # Placeholder - needs actual calibration data
)

# Initial values for chain 1
inits = (
    alpha = [3640, 3040, 2440, 1620, 1200, 640, missing],
    beta = [3490, 2490, 1940, 1230, 790, 500, 200],
    theta = [3630, 3620, 3560, 3545, 3500, 3030, 2845, 2800, 2500, 2430, 2170, 2125, 1990,
        1980, 1960, 1950, 1610, 1590, 1540, 1520, 1480, 1330, 1260, 1240, 1195, 1170,
        1120, 1120, 1030, 960, 880, 870, 820, 800, 630, 515, 305]
)

# Initial values for chain 2
inits_alternative = (
    alpha = [3690, 3090, 2490, 1670, 1250, 690, missing],
    beta = [3540, 2540, 1990, 1280, 940, 550, 250],
    theta = [3680, 3670, 3610, 3595, 3550, 3080, 2895, 2850, 2550, 2480, 2220, 2175, 2040,
        2030, 2010, 2000, 1660, 1640, 1590, 1570, 1530, 1380, 1310, 1290, 1245, 1220,
        1170, 1170, 1080, 1010, 1000, 1000, 1000, 1000, 680, 565, 355]
)

# Reference results from the example
reference_results = (
    var"alpha.desc[1]" = (mean = 3993.0, std = 167.8),
    var"alpha.desc[2]" = (mean = 3283.0, std = 181.8),
    var"alpha.desc[3]" = (mean = 2256.0, std = 149.2),
    var"alpha.desc[4]" = (mean = 1535.0, std = 79.5),
    var"alpha.desc[5]" = (mean = 1120.0, std = 88.58),
    var"alpha.desc[6]" = (mean = 718.7, std = 133.1),
    var"alpha.desc[7]" = (mean = 465.5, std = 60.24),
    var"beta.desc[1]" = (mean = 3728.0, std = 117.3),
    var"beta.desc[2]" = (mean = 2624.0, std = 195.1),
    var"beta.desc[3]" = (mean = 1806.0, std = 97.52),
    var"beta.desc[4]" = (mean = 1112.0, std = 85.24),
    var"beta.desc[5]" = (mean = 661.4, std = 54.69),
    var"beta.desc[6]" = (mean = 465.5, std = 60.24),
    var"beta.desc[7]" = (mean = 249.3, std = 115.1)
)

jama = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
