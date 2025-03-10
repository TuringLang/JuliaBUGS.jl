name = "St Veit-Klinglberg: Radiocarbon calibration with stratification"

model_def = @bugs begin
   theta[1] ~ dunif(theta[2], theta.max)
   theta[2] ~ dunif(theta[3], theta[1])
   theta[3] ~ dunif(theta[9], theta[2])
   theta[4] ~ dunif(theta[9], theta.max)
   theta[5] ~ dunif(theta[7], theta.max)
   theta[6] ~ dunif(theta[7], theta.max)
   theta[7] ~ dunif(theta[9], theta7max)
   theta7max = min(theta[5], theta[6])
   theta[8] ~ dunif(theta[9], theta.max)
   theta[9] ~ dunif(theta[10], theta9max)
   theta9max = min(min(theta[3], theta[4]), min(theta[7], theta[8]))
   theta[10] ~ dunif(theta[11], theta[9])
   theta[11] ~ dunif(0, theta[10])
   
   bound[1] = ranked(theta[1:8], 8)
   bound[2] = ranked(theta[1:8], 1)
   bound[3] = ranked(theta[9:11], 3)
   bound[4] = ranked(theta[9:11], 1)
   
   for j in 1:5
      theta[j + 11] ~ dunif(0, theta.max)
      within[j, 1] = 1 - step(bound[1] - theta[j + 11])
      for k in 2:4
         within[j, k] = step(bound[k - 1] - theta[j + 11]) - 
                        step(bound[k] - theta[j + 11])
      end
      within[j, 5] = step(bound[4] - theta[j + 11])
   end

   for i in 1:nDate
      X[i] ~ dnorm(mu[i], tau[i])
      tau[i] = 1/pow(sigma[i], 2)
      mu[i] = interp.lin(theta[i], calBP[:], C14BP[:])

      # monitor the following variable to smooth density of theta
      theta.smooth[i] = 10 * round(theta[i] / 10)
   end
end

original = """
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
"""

# Note: The calibration data (calBP and C14BP) is missing from the provided example
# This would need to be filled in with the actual calibration curve data
data = (
   nDate = 16,
   theta.max = 21000,
   X = [3275, 3270, 3400, 3190, 3420, 3370, 3435, 3160, 3340, 3270, 3200, 3390, 3480, 3250, 3115, 3460],
   sigma = [75, 80, 75, 75, 65, 75, 60, 70, 80, 75, 70, 80, 75, 75, 70, 70],
   # The calibration curve data would need to be added here
   calBP = [], # This needs to be filled with calibration curve calendar dates
   C14BP = []  # This needs to be filled with calibration curve radiocarbon dates
)

inits = (
   theta = [3700, 3600, 3550, 3504, 3586, 3800, 3529, 3525, 3500, 3500, 3402, 3542, 3492, 3618, 3148, 3638]
)

inits_alternative = (
   theta = [3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000]
)

# Reference results from the example
reference_results = (
   var"within[1,1]" = (mean = 0.1971, std = 0.3978),
   var"within[1,2]" = (mean = 0.7434, std = 0.4368),
   var"within[1,3]" = (mean = 0.025, std = 0.1561),
   var"within[1,4]" = (mean = 0.0317, std = 0.1752),
   var"within[1,5]" = (mean = 0.0028, std = 0.05284),
   var"within[2,1]" = (mean = 0.529, std = 0.4992),
   var"within[2,2]" = (mean = 0.4665, std = 0.4989),
   var"within[2,3]" = (mean = 0.0028, std = 0.05284),
   var"within[2,4]" = (mean = 0.0016, std = 0.03997),
   var"within[2,5]" = (mean = 0.0, std = 0.0),
   var"within[3,1]" = (mean = 0.00835, std = 0.091),
   var"within[3,2]" = (mean = 0.5372, std = 0.4986),
   var"within[3,3]" = (mean = 0.0937, std = 0.2914),
   var"within[3,4]" = (mean = 0.2674, std = 0.4426),
   var"within[3,5]" = (mean = 0.0933, std = 0.2909),
   var"within[4,1]" = (mean = 5.0E-5, std = 0.007071),
   var"within[4,2]" = (mean = 0.0419, std = 0.2004),
   var"within[4,3]" = (mean = 0.02885, std = 0.1674),
   var"within[4,4]" = (mean = 0.2789, std = 0.4485),
   var"within[4,5]" = (mean = 0.6503, std = 0.4769),
   var"within[5,1]" = (mean = 0.4454, std = 0.497),
   var"within[5,2]" = (mean = 0.5475, std = 0.4977),
   var"within[5,3]" = (mean = 0.0034, std = 0.05821),
   var"within[5,4]" = (mean = 0.0036, std = 0.05989),
   var"within[5,5]" = (mean = 5.0E-5, std = 0.007071)
)

st_veit_klinglberg = Example(
   name, model_def, original, data, inits, inits_alternative, reference_results)
