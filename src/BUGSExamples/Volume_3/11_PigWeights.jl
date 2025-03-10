name = "Pig Weights: Histogram smoothing with structured precision matrix"

model_def = @bugs begin
    y[1:s] ~ dmulti(th[1:s], n)
    sum.g = sum(g[:])
    # smoothed frequencies
    for i in 1:s
        Sm[i] = n * th[i]
        g[i] = exp(gam[i])
        th[i] = g[i] / sum.g
    end
    # prior on elements of AR Precision Matrix
    rho ~ dunif(0, 1)
    tau ~ dunif(0.5, 10)
    # MVN for logit parameters
    gam[1:s] ~ dmnorm(mu[:], T[:, :])
    for j in 1:s
        mu[j] = -log(s)
    end
    # Define Precision Matrix
    for j in 2:(s - 1)
        T[j, j] = tau * (1 + pow(rho, 2))
    end
    T[1, 1] = tau
    T[s, s] = tau
    for j in 1:(s - 1)
        T[j, j + 1] = -tau * rho
        T[j + 1, j] = T[j, j + 1]
    end
    for i in 1:(s - 1)
        for j in (2 + i):s
            T[i, j] = 0
            T[j, i] = 0
        end
    end
    # Or Could do in terms of covariance, which is simpler to write but slower
    # for i in 1:s
    #     for j in 1:s
    #         cov[i, j] = pow(rho, abs(i - j)) / tau
    #     end
    # end
    # T[1:s, 1:s] = inverse(cov[:, :])
end

original = """
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
"""

data = (
    y = [1, 1, 0, 7, 5, 10, 30, 30, 41, 48, 66, 72, 56, 46, 45, 22, 24, 12, 5, 0, 1],
    n = 522,
    s = 21
)

inits = (
    gam = [
    -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3]
)

inits_alternative = (
    gam = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0,
    -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0]
)

# Reference results would be added here when available
reference_results = (
    var"Sm[1]" = (mean = 1.539, std = 0.8977),
    var"Sm[2]" = (mean = 1.575, std = 0.8046),
    var"Sm[3]" = (mean = 1.956, std = 0.9074),
    var"Sm[4]" = (mean = 5.020, std = 1.716),
    var"Sm[5]" = (mean = 6.098, std = 1.915),
    var"Sm[6]" = (mean = 10.94, std = 2.756),
    var"Sm[7]" = (mean = 27.5, std = 4.68),
    var"Sm[8]" = (mean = 30.42, std = 4.877),
    var"Sm[9]" = (mean = 40.67, std = 5.781),
    var"Sm[10]" = (mean = 48.26, std = 6.399),
    var"Sm[11]" = (mean = 65.42, std = 7.298),
    var"Sm[12]" = (mean = 71.03, std = 7.519),
    var"Sm[13]" = (mean = 56.14, std = 6.582),
    var"Sm[14]" = (mean = 46.26, std = 6.019),
    var"Sm[15]" = (mean = 43.25, std = 5.965),
    var"Sm[16]" = (mean = 23.44, std = 4.195),
    var"Sm[17]" = (mean = 22.19, std = 4.193),
    var"Sm[18]" = (mean = 11.46, std = 2.839),
    var"Sm[19]" = (mean = 4.966, std = 1.700),
    var"Sm[20]" = (mean = 2.056, std = 1.001),
    var"Sm[21]" = (mean = 1.810, std = 0.9979)
)

pig_weights = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)