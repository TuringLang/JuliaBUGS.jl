# prepare data
data = JuliaBUGS.BUGSExamples.VOLUME_I[:rats].data
@unpack N, T, x, xbar, Y = data

inits = (
    alpha=[
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
        250,
    ],
    beta=[
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
    ],
    alpha_c=150,
    beta_c=10,
    tau_c=1,
    alpha_tau=1,
    beta_tau=1,
)

# prepare models
model_def = @bugsast begin
    for i in 1:N
        for j in 1:T
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
bugs_model = compile(model_def, data, inits);
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
svi = DynamicPPL.evaluate!!(
    dppl_model, SimpleVarInfo(Dict{VarName,Any}()), DynamicPPL.SamplingContext()
)[2]
keys(params_vi.values) == keys(svi.values) # test that the parameters match

for t in [true, false]
    compare_dppl_bugs_logps(dppl_model, bugs_model, t)
end
