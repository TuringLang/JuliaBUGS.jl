using Distributions

const DISTRIBUTIONS = [:dgamma, :dnorm, ]

dgamma(alpha, beta) = Gamma(alpha, beta)
dnorm(mu, sigma) = Normal(mu, sigma) # forget if need to sqrt the sigma

