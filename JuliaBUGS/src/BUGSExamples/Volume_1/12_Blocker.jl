name = "Blockers: random effects meta-analysis of clinical trials"

model_def = @bugs begin
    for i in 1:Num
        rc[i] ~ dbin(pc[i], nc[i])
        rt[i] ~ dbin(pt[i], nt[i])
        pc[i] = logistic(mu[i])
        pt[i] = logistic(mu[i] + delta[i])
        mu[i] ~ dnorm(0.0, 1.0e-5)
        delta[i] ~ dnorm(d, tau)
    end
    d ~ dnorm(0.0, 1.0e-6)
    tau ~ dgamma(0.001, 0.001)
    var"delta.new" ~ dnorm(d, tau)
    sigma = 1 / sqrt(tau)
end

original = """
model {
    for( i in 1 : Num ) {
        rc[i] ~ dbin(pc[i], nc[i])
        rt[i] ~ dbin(pt[i], nt[i])
        logit(pc[i]) <- mu[i]
        logit(pt[i]) <- mu[i] + delta[i]
        mu[i] ~ dnorm(0.0,1.0E-5)
        delta[i] ~ dnorm(d, tau)
    }
    d ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    delta.new ~ dnorm(d, tau)
    sigma <- 1 / sqrt(tau)
}
"""

data = (
    rt = [3, 7, 5, 102, 28, 4, 98, 60, 25, 138, 64,
        45, 9, 57, 25, 33, 28, 8, 6, 32, 27, 22],
    nt = [38, 114, 69, 1533, 355, 59, 945, 632, 278, 1916, 873,
        263, 291, 858, 154, 207, 251, 151, 174, 209, 391, 680],
    rc = [3, 14, 11, 127, 27, 6, 152, 48, 37, 188, 52,
        47, 16, 45, 31, 38, 12, 6, 3, 40, 43, 39],
    nc = [39, 116, 93, 1520, 365, 52, 939, 471, 282, 1921, 583,
        266, 293, 883, 147, 213, 122, 154, 134, 218, 364, 674],
    Num = 22
)

inits = (
    d = 0,
    var"delta.new" = 0,
    tau = 1,
    mu = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    delta = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
)
inits_alternative = (
    d = 2,
    var"delta.new" = 2,
    tau = 0.1,
    mu = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
    delta = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
)

reference_results = nothing

blockers = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
