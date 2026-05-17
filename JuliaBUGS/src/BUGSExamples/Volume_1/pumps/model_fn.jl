@model function pumps((; x, theta, alpha, beta), N, t)
    for i in 1:N
        theta[i] ~ dgamma(alpha, beta)
        lambda[i] = theta[i] * t[i]
        x[i] ~ dpois(lambda[i])
    end
    alpha ~ dexp(1)
    beta ~ dgamma(0.1, 1.0)
end
