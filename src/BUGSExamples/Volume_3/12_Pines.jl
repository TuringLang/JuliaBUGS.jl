name = "Bayes Factors: Using pseudo priors with Carlin and Chib method"

model_def = @bugs begin
    # standardise data
    for i in 1:N
        Ys[i] = (Y[i] - mean(Y[:])) / sd(Y[:])
        xs[i] = (x[i] - mean(x[:])) / sd(x[:])
        zs[i] = (z[i] - mean(z[:])) / sd(z[:])
    end

    # model node
    j ~ dcat(p[:])
    p[1] = 0.9995
    p[2] = 1 - p[1]  # use for joint modelling
    # p[1] = 1 p[2] = 0 # include for estimating Model 1
    # p[1] = 0 p[2] = 1 # include for estimating Model 2
    pM2 = step(j - 1.5)

    # model structure
    for i in 1:N
        mu[1, i] = alpha + beta * xs[i]
        mu[2, i] = gamma + delta * zs[i]
        Ys[i] ~ dnorm(mu[j, i], tau[j])
    end

    # Model 1
    alpha ~ dnorm(mu.alpha[j], tau.alpha[j])
    beta ~ dnorm(mu.beta[j], tau.beta[j])
    tau[1] ~ dgamma(r1[j], l1[j])
    # estimation priors
    mu.alpha[1] = 0
    tau.alpha[1] = 1.0E-6
    mu.beta[1] = 0
    tau.beta[1] = 1.0E-4
    r1[1] = 0.0001
    l1[1] = 0.0001
    # pseudo-priors
    mu.alpha[2] = 0
    tau.alpha[2] = 256
    mu.beta[2] = 1
    tau.beta[2] = 256
    r1[2] = 30
    l1[2] = 4.5

    # Model 2
    gamma ~ dnorm(mu.gamma[j], tau.gamma[j])
    delta ~ dnorm(mu.delta[j], tau.delta[j])
    tau[2] ~ dgamma(r2[j], l2[j])
    # pseudo-priors
    mu.gamma[1] = 0
    tau.gamma[1] = 400
    mu.delta[1] = 1
    tau.delta[1] = 400
    r2[1] = 46
    l2[1] = 4.5
    # estimation priors
    mu.gamma[2] = 0
    tau.gamma[2] = 1.0E-6
    mu.delta[2] = 0
    tau.delta[2] = 1.0E-4
    r2[2] = 0.0001
    l2[2] = 0.0001
end

original = """
model{
# standardise data
for(i in 1:N){
Ys[i] <- (Y[i] - mean(Y[])) / sd(Y[])
xs[i] <- (x[i] - mean(x[])) / sd(x[])
zs[i] <- (z[i] - mean(z[])) / sd(z[])
}

# model node
j ~ dcat(p[])
p[1] <- 0.9995 p[2] <- 1 - p[1] # use for joint modelling
# p[1] <- 1 p[2] <- 0 # include for estimating Model 1
# p[1] <- 0 p[2] <-1 # include for estimating Model 2
pM2 <- step(j - 1.5)

# model structure
for(i in 1 : N){
mu[1, i] <- alpha + beta * xs[i]
mu[2, i] <- gamma + delta*zs[i]
Ys[i] ~ dnorm(mu[j, i], tau[j])
}

# Model 1
alpha ~ dnorm(mu.alpha[j], tau.alpha[j])
beta ~ dnorm(mu.beta[j], tau.beta[j])
tau[1] ~ dgamma(r1[j], l1[j])
# estimation priors
mu.alpha[1]<- 0 tau.alpha[1] <- 1.0E-6
mu.beta[1] <- 0 tau.beta[1] <- 1.0E-4
r1[1] <- 0.0001 l1[1] <- 0.0001
# pseudo-priors
mu.alpha[2]<- 0 tau.alpha[2] <- 256
mu.beta[2] <- 1 tau.beta[2] <- 256
r1[2] <- 30 l1[2] <- 4.5

# Model 2
gamma ~ dnorm(mu.gamma[j], tau.gamma[j])
delta ~ dnorm(mu.delta[j], tau.delta[j])
tau[2] ~ dgamma(r2[j], l2[j])
# pseudo-priors
mu.gamma[1] <- 0 tau.gamma[1] <- 400
mu.delta[1] <- 1 tau.delta[1] <- 400
r2[1] <- 46 l2[1] <- 4.5
# estimation priors
mu.gamma[2] <- 0 tau.gamma[2] <- 1.0E-6
mu.delta[2] <- 0 tau.delta[2] <- 1.0E-4
r2[2] <- 0.0001 l2[2] <- 0.0001
}
"""

data = (
    N = 42,
    Y = [3040, 2470, 3610, 3480, 3810, 2330, 1800, 3110, 3160, 2310,
         4360, 1880, 3670, 1740, 2250, 2650, 4970, 2620, 2900, 1670,
         2540, 3840, 3800, 4600, 1900, 2530, 2920, 4990, 1670, 3310,
         3450, 3600, 2850, 1590, 3770, 3850, 2480, 3570, 2620, 1890,
         3030, 3030],
    x = [29.2, 24.7, 32.3, 31.3, 31.5, 24.5, 19.9, 27.3, 27.1, 24.0,
         33.8, 21.5, 32.2, 22.5, 27.5, 25.6, 34.5, 26.2, 26.7, 21.1,
         24.1, 30.7, 32.7, 32.6, 22.1, 25.3, 30.8, 38.9, 22.1, 29.2,
         30.1, 31.4, 26.7, 22.1, 30.3, 32.0, 23.2, 30.3, 29.9, 20.8,
         33.2, 28.2],
    z = [25.4, 22.2, 32.2, 31.0, 30.9, 23.9, 19.2, 27.2, 26.3, 23.9,
         33.2, 21.0, 29.0, 22.0, 23.8, 25.3, 34.2, 25.7, 26.4, 20.0,
         23.9, 30.7, 32.6, 32.5, 20.8, 23.1, 29.8, 38.1, 21.3, 28.5,
         29.2, 31.4, 25.9, 21.4, 29.8, 30.6, 22.6, 30.3, 23.8, 18.4,
         29.4, 28.2]
)

inits = (
    j = 2,
    tau = [1, 1],
    alpha = 0,
    beta = 0,
    gamma = 0,
    delta = 0
)

inits_alternative = (
    j = 1,
    tau = [0.1, 0.1],
    alpha = 1.0,
    beta = 1.0,
    gamma = 1.0,
    delta = 1.0
)

# Reference results from the example
reference_results = (
    pM2 = (mean = 0.6402, std = 0.48),
)

bayes_factors = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
