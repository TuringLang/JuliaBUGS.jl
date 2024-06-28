name = "Hearts: a mixture model for count data"

model_def = @bugs begin
    for i in 1:N
        y[i] ~ dbin(P[state1[i]], t[i])
        state[i] ~ dbern(theta)
        state1[i] = state[i] + 1
        t[i] = x[i] + y[i]
        prop[i] = P[state1[i]]
    end
    P[1] = p
    P[2] = 0
    p = logistic(alpha)
    alpha ~ dnorm(0, 1.0E-4)
    beta = exp(alpha)
    theta = logistic(delta)
    delta ~ dnorm(0, 1.0E-4)
end

original = """
model
{
   for (i in 1 : N) {
      y[i] ~ dbin(P[state1[i]], t[i])
      state[i] ~ dbern(theta)
      state1[i] <- state[i] + 1
      t[i] <- x[i] + y[i]
      prop[i] <- P[state1[i]]
   }
   P[1] <- p
   P[2] <- 0
   logit(p) <- alpha
   alpha ~ dnorm(0,1.0E-4)
   beta <- exp(alpha)
   logit(theta) <- delta
   delta ~ dnorm(0, 1.0E-4)
}
"""

data = (x = [6, 9, 17, 22, 7, 5, 5, 14, 9, 7, 9, 51],
    y = [5, 2, 0, 0, 2, 1, 0, 0, 0, 0, 13, 0], N = 12)

inits = (delta = 0, alpha = 0)
inits_alternative = (delta = 2, alpha = 2)

reference_results = (
    alpha = (mean = -0.4786, std = 0.2764),
    beta = (mean = 0.6434, std = 0.1777),
    delta = (mean = 0.3172, std = 0.6269),
    theta = (mean = 0.5721, std = 0.141)
)

hearts = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
