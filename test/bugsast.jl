# more examples can be found here: https://www.mrc-bsu.cam.ac.uk/software/bugs/

# b[1][1] should error because arrays in BUGS are tensors
# @test_throws(ErrorException,  
@test_throws ErrorException JuliaBUGS.bugsast(:(b[1][1] ~ dnorm(0, 1)))

# bugsast
regression = @bugs begin
    for i in 1:N
        Y[i] ~ dnorm(μ[i], τ)
        μ[i] = α + β * (x[i] - x̄)
    end
    τ ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ)
    logτ = log(τ)
    α = dnorm(0.0, 1e-6)
    β = dnorm(0.0, 1e-6)
end

regression_data = (x=[1, 2, 3, 4, 5], Y=[1, 3, 3, 3, 5], x̄=3, N=5)

_rats = @bugs begin
    for i in 1:N
        for j in 1:T
            Y[i, j] ~ dnorm(μ[i, j], τ_c)
            μ[i, j] = α[i] + β[i] * (x[j] - x̄)
        end
        α[i] ~ dnorm(α_c, α_τ)
        β[i] ~ dnorm(β_c, β_τ)
    end

    τ_c ~ dgamma(0.001, 0.001)
    σ = 1 / sqrt(τ_c)
    α_c ~ dnorm(0.0, 1e-6)
    α_τ ~ dgamma(0.001, 0.001)
    β_c ~ dnorm(0.0, 1e-6)
    β_τ ~ dgamma(0.001, 0.001)
    α₀ = α_c - x̄ * β_c
end

_hearts = @bugs begin
    for i in 1:N
        y[i] ~ dbin(q[i], t[i])
        q[i] = P[state1[i]]
        state1[i] = state[i] + 1
        state[i] ~ dbern(θ)
        t[i] = x[i] + y[i]
    end

    P[1] = p
    P[2] = 0
    p = logistic(α)
    α ~ dnorm(0, 1e-4)
    β = exp(α)
    θ = logistic(δ)
    delta ~ dnorm(0, 1e-4)
end

_regions1 = @bugs begin
    x[1] = 10
    x[2] ~ dnorm(0, 1)
    for i in 1:x[1]
        y[i] = i
    end
end

_regions2 = @bugs begin
    x[2] ~ dnorm(0, 1)
    for i in 1:x[1]
        y[i] = i
    end
end

_regions3 = @bugs begin
    x1 = 10
    x2 ~ dnorm(0, 1)
    for i in 1:x1
        y[i] = i
    end
end

_interpolated = @bugs begin
    x = exp($(Expr(:call, :f, 10)))
    y = x[$("sdf")] # muahaha...
end

# bugsmodel
_kidney_transplants = @bugs("""
model{
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
}
""")

growth_curve = @bugs(
    """
for (i in 1:5) {
    y[i] ~ dnorm(mu[i], tau)
    mu[i] <- alpha + beta*(x[i] - mean(x[]))
}

alpha ~ dflat()
beta ~ dflat()
tau <- 1/sigma2
log(sigma2) <- 2*log.sigma
log.sigma ~ dflat()
""",
    true,
    true
)

jaws = @bugs(
    """
for (i in 1:20) { Y[i, 1:4] ~ dmnorm(mu[], Sigma.inv[,]) }
for (j in 1:4) { mu[j] <- alpha + beta*x[j] }
alpha ~ dnorm(0, 0.0001)
beta ~ dnorm(0, 0.0001)
Sigma.inv[1:4, 1:4] ~ dwish(R[,], 4)
Sigma[1:4, 1:4] <- inverse(Sigma.inv[,])
""",
    true,
    true
)

truncation = @bugs(
    """
a ~ dwish(R[,], 4) C (0, 1)
a ~ dwish(R[,], 4) C (,1)
a ~ dwish(R[,], 4) C (0,)
a ~ dwish(R[,], 4) T (0, 1)
""",
    true,
    true
)
