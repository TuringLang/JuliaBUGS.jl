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
        for k in 1:3
            theta[i, k] ~ dnorm(mu[k], tau[k])
        end
    end
    tauC ~ dgamma(1.0E-3, 1.0E-3)
    var"sigma.C" = 1 / sqrt(tauC)
    for k in 1:3
        mu[k] ~ dnorm(0, 1.0E-4)
        tau[k] ~ dgamma(1.0E-3, 1.0E-3)
        sigma[k] = 1 / sqrt(tau[k])
    end
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
"""

data = (n = 7, K = 5, x = [118.00, 484.00, 664.00, 1004.00, 1231.00, 1372.00, 1582.00],
    Y = [30.00 58.00 87.00 115.00 120.00 142.00 145.00
         33.00 69.00 111.00 156.00 172.00 203.00 203.00
         30.00 51.00 75.00 108.00 115.00 139.00 140.00
         32.00 62.00 112.00 167.00 179.00 209.00 214.00
         30.00 49.00 81.00 125.00 142.00 174.00 177.00]
)

inits = (theta = [5 2 -6
                  5 2 -6
                  5 2 -6
                  5 2 -6
                  5 2 -6],
    mu = [5, 2, -6], tau = [20, 20, 20], tauC = 20)

inits_alternative = (
    theta = [3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0
             3.0 1.0 -1.0],
    mu = [3.0, 1.0, -1.0], tau = [2, 2, 2], tauC = 2)

reference_results = (
    var"mu[1]" = (mean = 5.257, sd = 0.1252, mc_error = 0.002462,
        quantile_2_5 = 5.013, quantile_97_5 = 5.501, n_eff = 5001, Rhat = 20000),
    var"mu[2]" = (mean = 2.198, sd = 0.1171, mc_error = 0.00461, quantile_2_5 = 1.975,
        quantile_97_5 = 2.421, n_eff = 5001, Rhat = 20000),
    var"mu[3]" = (mean = -5.874, sd = 0.09403, mc_error = 0.004655, quantile_2_5 = -6.058,
        quantile_97_5 = -5.701, n_eff = 5001, Rhat = 20000),
    var"sigma[1]" = (
        mean = 0.2369, sd = 0.1258, mc_error = 0.00241, quantile_2_5 = 0.09734,
        quantile_97_5 = 0.5436, n_eff = 5001, Rhat = 20000),
    var"sigma[2]" = (
        mean = 0.1346, sd = 0.1166, mc_error = 0.003597, quantile_2_5 = 0.02544,
        quantile_97_5 = 0.4308, n_eff = 5001, Rhat = 20000),
    var"sigma[3]" = (
        mean = 0.1014, sd = 0.08572, mc_error = 0.003506, quantile_2_5 = 0.02441,
        quantile_97_5 = 0.3247, n_eff = 5001, Rhat = 20000),
    var"sigma.C" = (mean = 7.972, sd = 1.188, mc_error = 0.02552, quantile_2_5 = 6.035,
        quantile_97_5 = 10.68, n_eff = 5001, Rhat = 20000)
)

orange_trees = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
