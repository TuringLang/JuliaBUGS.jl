@model function surgical_realistic((; b, r, mu, tau), N, n)
    for i in 1:N
        b[i] ~ dnorm(mu, tau)
        r[i] ~ dbin(p[i], n[i])
        p[i] = logistic(b[i])
    end
    var"pop.mean" = exp(mu) / (1 + exp(mu))
    mu ~ dnorm(0.0, 1.0e-6)
    sigma = 1 / sqrt(tau)
    tau ~ dgamma(0.001, 0.001)
end
