name = "Air: Berkson measurement error"

model_def = @bugs begin
    for j in 1:J
        y[j] ~ dbin(p[j], n[j])
        p[j] = logistic(theta[1] + theta[2] * X[j])
        X[j] ~ dnorm(mu[j], tau)
        mu[j] = alpha + beta * Z[j]
    end
    theta[1] ~ dnorm(0.0, 0.001)
    theta[2] ~ dnorm(0.0, 0.001)
end

original = """
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
"""

data = (J = 3, y = [21, 20, 15], n = [48, 34, 21],
    Z = [10, 30, 50], tau = 0.01234, alpha = 4.48, beta = 0.76)

inits = (theta = [0.0, 0.0], X = [0.0, 0.0, 0.0])
inits_alternative = (theta = [1.0, 1.0], X = [10.0, 30.0, 40.0])

reference_results = (
    var"X[1]" = (mean = 13.48, std = 8.403),
    var"X[2]" = (mean = 27.35, std = 7.462),
    var"X[3]" = (mean = 40.73, std = 8.798),
    var"theta[1]" = (mean = -1.061, std = 2.42),
    var"theta[2]" = (mean = 0.0519, std = 0.09807)
)

air = Example(name, model_def, original, data, inits, inits_alternative, reference_results)
