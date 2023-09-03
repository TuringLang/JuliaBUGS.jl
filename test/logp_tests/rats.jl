# prepare data
data = load_dictionary(:rats, :data, true)
inits = load_dictionary(:rats, :init, true)

@unpack N, T, x, xbar, Y = data

# prepare models
model_def = @bugs begin
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

vi, bugs_logp = get_vi_logp(bugs_model, false)
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test params_in_dppl_model(dppl_model) == keys(params_vi)

_, dppl_logp = get_vi_logp(dppl_model, vi, false)
@test bugs_logp ≈ -174029.387 rtol = 1E-6 # reference value from ProbPALA
@test bugs_logp ≈ dppl_logp rtol = 1E-6

_, bugs_logp = get_vi_logp(bugs_model, true)
vi = prepare_transformed_varinfo(bugs_model)
_, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
