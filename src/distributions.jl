using Distributions

dgamma(alpha, beta) = Gamma(alpha, beta)
dnorm(mu, sigma) = Normal(mu, sigma) # forget if need to sqrt the sigma
dact(p) = Categorical(p)

# Alternative
# DISTRIBUTIONS = Dict(:dgamma => :Gamma)
