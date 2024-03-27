model_def = JuliaBUGS.BUGSExamples.Volume_1.rats.model_def
data = JuliaBUGS.BUGSExamples.Volume_1.rats.data
inits = JuliaBUGS.BUGSExamples.Volume_1.rats.inits

bugs_model = compile(model_def, data, inits);
vi = bugs_model.varinfo

@model function rats(Y, x, xbar, N, T)
    var"tau.c" ~ dgamma(0.001, 0.001)
    sigma = 1 / sqrt(var"tau.c")

    var"alpha.c" ~ dnorm(0.0, 1.0E-6)
    var"alpha.tau" ~ dgamma(0.001, 0.001)

    var"beta.c" ~ dnorm(0.0, 1.0E-6)
    var"beta.tau" ~ dgamma(0.001, 0.001)

    alpha0 = var"alpha.c" - xbar * var"beta.c"

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)

    for i in 1:N
        alpha[i] ~ dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ dnorm(var"beta.c", var"beta.tau")

        for j in 1:T
            mu = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ dnorm(mu, var"tau.c")
        end
    end

    return sigma, alpha0
end
(; N, T, x, xbar, Y) = data
dppl_model = rats(Y, x, xbar, N, T)

bugs_model = JuliaBUGS.settrans(bugs_model, false)
bugs_logp = JuliaBUGS.evaluate!!(bugs_model, DefaultContext())[2]
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test keys(
    DynamicPPL.evaluate!!(
        dppl_model, SimpleVarInfo(Dict{VarName,Any}()), DynamicPPL.SamplingContext()
    )[2],
) == keys(params_vi)

dppl_logp =
    DynamicPPL.evaluate!!(
        dppl_model, DynamicPPL.settrans!!(vi, false), DynamicPPL.DefaultContext()
    )[2].logp
@test bugs_logp ≈ -174029.387 rtol = 1E-6 # reference value from ProbPALA
@test bugs_logp ≈ dppl_logp rtol = 1E-6

dppl_logp =
    DynamicPPL.evaluate!!(
        dppl_model, get_params_varinfo(bugs_model), DynamicPPL.DefaultContext()
    )[2].logp
bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, true), DefaultContext())[2]
@test bugs_logp ≈ dppl_logp rtol = 1E-6

@test bugs_model.untransformed_param_length ==
    LogDensityProblems.dimension(DynamicPPL.LogDensityFunction(dppl_model))
