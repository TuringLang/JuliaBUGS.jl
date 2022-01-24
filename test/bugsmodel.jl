kidney_transplants = bugsmodel"""
for (i in 1:N) {
    Score[i] ~ dcat(p[i,])
    p[i,1] <- 1 - Q[i,1]

    for (r in 2:5) {
        p[i,r] <- Q[i,r-1] - Q[i,r]
    }

    p[i,6] <- Q[i,5]

    for (r in 1:5) {
        logit(Q[i,r]) <- b.apd*lAPD[i] - c[r]
    }
}

for (i in 1:5) {
    dc[i] ~ dunif(0, 20)
}

c[1] <- dc[1]

for (i in 2:5) {
    c[i] <- c[i-1] + dc[i]
}

b.apd ~ dnorm(0, 1.0E-03)
or.apd <- exp(b.apd)
"""

growth_curve = bugsmodel"""
for (i in 1:5) {
    y[i] ~ dnorm(mu[i], tau)
    mu[i] <- alpha + beta*(x[i] - mean(x[]))
}

alpha ~ dflat()
beta ~ dflat()
tau <- 1/sigma2
log(sigma2) <- 2*log.sigma
log.sigma ~ dflat()
"""

jaws = bugsmodel"""
for (i in 1:20) { Y[i, 1:4] ~ dmnorm(mu[], Sigma.inv[,]) }
for (j in 1:4) { mu[j] <- alpha + beta*x[j] }
alpha ~ dnorm(0, 0.0001)
beta ~ dnorm(0, 0.0001)
Sigma.inv[1:4, 1:4] ~ dwish(R[,], 4)
Sigma[1:4, 1:4] <- inverse(Sigma.inv[,])
"""
