name = "Surgical: Institutional ranking"

# simplistic model
model_def_simplistic = @bugs begin
    for i in 1:N
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    end
end

original_simplistic = """
model {
    for( i in 1 : N ) {
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    }
}
"""

data = (
    n = [47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
    r = [0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
    N = 12
)

inits_simplistic = (p = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1],)
inits_alternative_simplistic = (p = [
    0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],)

# more realistic model
model_def_realistic = @bugs begin
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

original_realistic = """
model {
    for( i in 1 : N ) {
        b[i] ~ dnorm(mu,tau)
        r[i] ~ dbin(p[i],n[i])
        p[i] <- logistic(b[i])
    }
    pop.mean <- exp(mu) / (1 + exp(mu))
    mu ~ dnorm(0.0,1.0E-6)
    sigma <- 1 / sqrt(tau)
    tau ~ dgamma(0.001,0.001)
}
"""

inits_realistic = (
    b = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], tau = 1, mu = 0)
inits_alternative_realistic = (
    b = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], tau = 0.1, mu = 1.0)

reference_results = nothing

surgical_simple = Example(
    name, model_def_simplistic, original_simplistic, data, inits_simplistic,
    inits_alternative_simplistic, reference_results)

surgical_realistic = Example(
    name, model_def_realistic, original_realistic, data, inits_realistic,
    inits_alternative_realistic, reference_results)
