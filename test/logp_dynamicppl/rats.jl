# prepare data
data = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].data
@unpack N, T, x, xbar, Y = data

inits = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].inits[1]

# prepare models
model_def = @bugsast begin
    for i in 1 : N
        for j in 1 : T
          Y[i, j] ~ dnorm(mu[i, j], tau_c)
          mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
        end
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        beta[i] ~ dnorm(beta_c, beta_tau)
    end
    tau_c ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau_c)
    alpha_c ~ dnorm(0.0, 1.0E-6)   
    alpha_tau ~ dgamma(0.001, 0.001)
    beta_c ~ dnorm(0.0, 1.0E-6)
    beta_tau ~ dgamma(0.001, 0.001)
    alpha0 = alpha_c - xbar * beta_c
end
bugs_model = compile(model_def, data, inits)
params_vi = JuliaBUGS.get_params_varinfo(bugs_model)

@model function rats(Y, x, xbar, N, T)
    tau_c ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(tau_c)

    alpha_c ~ dnorm(0.0, 1.0E-6)
    alpha_tau ~ dgamma(0.001, 0.001)

    beta_c ~ dnorm(0.0, 1.0E-6)
    beta_tau ~ dgamma(0.001, 0.001)

    alpha0 = alpha_c - xbar * beta_c

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)

    for i in 1:N
        alpha[i] ~ dnorm(alpha_c, alpha_tau)
        beta[i] ~ dnorm(beta_c, beta_tau)

        for j in 1:T
            mu = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ dnorm(mu, tau_c)
        end
    end

    return sigma, alpha0
end

dppl_model = rats(Y, x, xbar, N, T)
svi = DynamicPPL.evaluate!!(dppl_model, SimpleVarInfo(Dict{VarName, Any}()), DynamicPPL.SamplingContext())[2]
keys(params_vi.values) == keys(svi.values) # test that the parameters match

bugs_logp = getlogp(
    evaluate!!(DynamicPPL.settrans!!(bugs_model, false), JuliaBUGS.DefaultContext())
)

turing_logp = getlogp(
    evaluate!!(model, settrans!!(svi_b, false), DynamicPPL.DefaultContext())[2]
)

bugs_logp = getlogp(
    evaluate!!(DynamicPPL.settrans!!(bugs_model, true), JuliaBUGS.DefaultContext())
)

turing_logp = getlogp(
    evaluate!!(model, settrans!!(svi_b, true), DynamicPPL.DefaultContext())[2]
)

