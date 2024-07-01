name = "Orange Trees: Non-linear growth curve"

model_def = @bugs begin
    for i in 1:K
        for j in 1:n
            Y[i, j] ~ dnorm(eta[i, j], tauC)
            eta[i, j] = phi[i, 1] / (1 + phi[i, 2] * exp(phi[i, 3] * x[j]))
        end
        phi[i, 1] = exp(theta[i, 1])
        phi[i, 2] = exp(theta[i, 2]) - 1
        phi[i, 3] = -exp(theta[i, 3])
        theta[i, 1:3] ~ dmnorm(mu[1:3], tau[1:3, 1:3])
    end
    mu[1:3] ~ dmnorm(mean[1:3], prec[1:3, 1:3])
    tau[1:3, 1:3] ~ dwish(R[1:3, 1:3], 3)
    sigma2[1:3, 1:3] = inverse(tau[1:3, 1:3])
    for i in 1:3
        sigma[i] = sqrt(sigma2[i, i])
    end
    tauC ~ dgamma(1.0E-3, 1.0E-3)
    sigmaC = 1 / sqrt(tauC)
end

original = """
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
"""

data = (n = 7, K = 5, x = [118.00, 484.00, 664.00, 1004.00, 1231.00, 1372.00, 1582.00],
    Y = [30.00 58.00 87.00 115.00 120.00 142.00 145.00
         33.00 69.00 111.00 156.00 172.00 203.00 203.00
         30.00 51.00 75.00 108.00 115.00 139.00 140.00
         32.00 62.00 112.00 167.00 179.00 209.00 214.00
         30.00 49.00 81.00 125.00 142.00 174.00 177.00],
    mean = [0, 0, 0],
    R = [0.1 0 0
         0 0.1 0
         0 0 0.1],
    prec = [1.0E-6 0 0
            0 1.0E-6 0
            0 0 1.0E-6])

inits = (theta = [5 2 -6
                  5 2 -6
                  5 2 -6
                  5 2 -6
                  5 2 -6],
    mu = [5, 2, -6],
    tau = [0.1 0 0
           0 0.1 0
           0 0 0.1],
    tauC = 20
)

inits_alternative = (
    theta = [3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0],
    mu = [3.0, 1.0, -1.0],
    tau = [2.0 0 0
           0 2.0 0
           0 0 2.0],
    tauC = 2)

reference_results = (
    var"mu[1]" = (mean = 5.266, std = 0.1363),
    var"mu[2]" = (mean = 2.196, std = 0.1629),
    var"mu[3]" = (mean = -5.885, std = 0.1421),
    var"sigma[1]" = (mean = 0.2587, std = 0.1145),
    var"sigma[2]" = (mean = 0.2636, std = 0.1282),
    var"sigma[3]" = (mean = 0.2302, std = 0.1073),
    var"sigmaC" = (mean = 7.902, std = 1.207)
)

orange_trees_multivariate = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
