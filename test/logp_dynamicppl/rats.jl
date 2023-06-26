bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].inits[1]

@unpack N, T, x, xbar, Y = data

@model function rats(Y, x, xbar, N, T)
    var"alpha.c" ~ dnorm(0.0, 1.0E-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)
    var"beta.c" ~ dnorm(0.0, 1.0E-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)
    var"tau.c" ~ dgamma(0.001, 0.001)

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)
    mu = Matrix{Real}(undef, N, T)

    for i in 1:N
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")

        for j in 1:T
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ dnorm(mu[i, j], var"tau.c")
        end
    end

    sigma = 1 / sqrt(var"tau.c")
    alpha0 = var"alpha.c" - xbar * var"beta.c"

    return alpha0, sigma
end

turing_model = rats(Y, x, xbar, N, T)

bugs_model = compile(bugs_model_def, data, inits)

vi = deepcopy(bugs_model.varinfo)

turing_logp_no_trans = getlogp(
    last(
        DynamicPPL.evaluate!!(
            turing_model, DynamicPPL.settrans!!(vi, false), DynamicPPL.DefaultContext()
        ),
    ),
)

julia_bugs_logp_no_trans = getlogp(
    evaluate!!(
        DynamicPPL.settrans!!(bugs_model, false), 
        JuliaBUGS.DefaultContext()
    )
)

turing_logp_with_trans = getlogp(
    last(
        DynamicPPL.evaluate!!(
            turing_model, DynamicPPL.settrans!!(vi, true), DynamicPPL.DefaultContext()
        ),
    ),
)

julia_bugs_logp_with_trans = getlogp(
    evaluate!!(
        DynamicPPL.settrans!!(bugs_model, true), 
        JuliaBUGS.DefaultContext()
    )
)