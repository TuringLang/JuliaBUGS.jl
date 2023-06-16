arg_list = Dict(
    :rats => [:Y, :x, :xbar, :N, :T],
    :blockers => [:rc, :rt, :nc, :nt, :Num],
    :bones => [:grade, :nChild, :nInd, :ncat],
    :dogs => [:Y, :Dogs, :Trials],
)

@model function blockers(rc, rt, nc, nt, Num)
    d ~ dnorm(0.0, 1.0E-6)
    tau ~ dgamma(0.001, 0.001)

    mu = Vector{Real}(undef, Num)
    delta = Vector{Real}(undef, Num)
    pc = Vector{Real}(undef, Num)
    pt = Vector{Real}(undef, Num)

    for i in 1:Num
        mu[i] ~ dnorm(0.0, 1.0E-5)
        delta[i] ~ dnorm(d, tau)

        pc[i] = logistic(mu[i])
        pt[i] = logistic(mu[i] + delta[i])

        rc[i] ~ dbin(pc[i], nc[i])
        rt[i] ~ dbin(pt[i], nt[i])
    end

    var"delta.new" ~ dnorm(d, tau)
    sigma = 1 / sqrt(tau)

    return sigma
end

@model function bones(grade, nChild, nInd, ncat)
    theta = Vector{Real}(undef, nChild)
    Q = Array{Real}(undef, nChild, nInd, maximum(ncat))
    p = Array{Real}(undef, nChild, nInd, maximum(ncat))
    gamma = Array{Real}(undef, nInd, maximum(ncat) - 1)
    delta = Vector{Real}(undef, nInd)
    cumulative_grade = Array{Real}(undef, nChild, nInd)

    for i in 1:nChild
        theta[i] ~ dnorm(0.0, 0.001)

        for j in 1:nInd
            for k in 1:(ncat[j] - 1)
                Q[i, j, k] = logistic(delta[j] * (theta[i] - gamma[j, k]))
            end
        end

        for j in 1:nInd
            p[i, j, 1] = 1 - Q[i, j, 1]

            for k in 2:(ncat[j] - 1)
                p[i, j, k] = Q[i, j, k - 1] - Q[i, j, k]
            end

            p[i, j, ncat[j]] = Q[i, j, ncat[j] - 1]
            grade[i, j] ~ dcat(p[i, j, 1:ncat[j]])
        end
    end
end

@model function dogs(Y, Dogs, Trials)
    alpha ~ dunif(-10, -0.00001)
    beta ~ dunif(-10, -0.00001)

    xa = Matrix{Real}(undef, Dogs, Trials)
    xs = Matrix{Real}(undef, Dogs, Trials)
    p = Matrix{Real}(undef, Dogs, Trials)
    y = Matrix{Real}(undef, Dogs, Trials)

    for i in 1:Dogs
        xa[i, 1] = 0
        xs[i, 1] = 0
        p[i, 1] = 0

        for j in 2:Trials
            xa[i, j] = sum(Y[i, 1:j-1])
            xs[i, j] = j - 1 - xa[i, j]
            p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
            y[i, j] = 1 - Y[i, j]
            y[i, j] ~ dbern(p[i, j])
        end
    end

    A = exp(alpha)
    B = exp(beta)

    return A, B
end

@model function rats(Y, x, xbar, N, T)
    var"alpha.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"alpha.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"beta.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"beta.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"tau.c" ~ JuliaBUGS.dgamma(0.001, 0.001)

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)
    mu = Matrix{Real}(undef, N, T)

    for i in 1:N
        alpha[i] ~ JuliaBUGS.dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ JuliaBUGS.dnorm(var"beta.c", var"beta.tau")

        for j in 1:T
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ JuliaBUGS.dnorm(mu[i, j], var"tau.c")
        end
    end

    sigma = 1 / sqrt(var"tau.c")
    alpha0 = var"alpha.c" - xbar * var"beta.c"

    return alpha0, sigma
end

