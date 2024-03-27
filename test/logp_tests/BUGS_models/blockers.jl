bugs_model_def = JuliaBUGS.BUGSExamples.Volume_1.blockers.model_def
data = JuliaBUGS.BUGSExamples.blockers.Volume_1.data
inits = JuliaBUGS.BUGSExamples.blockers.Volume_1.inits

bugs_model = compile(bugs_model_def, data, inits)
vi = bugs_model.varinfo

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

(; rt, nt, rc, nc, Num) = data
dppl_model = blockers(rc, rt, nc, nt, Num)

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, false), DefaultContext())[2]
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
@test bugs_logp ≈ -8418.416388 rtol = 1E-6
@test bugs_logp ≈ dppl_logp rtol = 1E-6

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, true), DefaultContext())[2]
dppl_logp =
    DynamicPPL.evaluate!!(
        dppl_model, get_params_varinfo(bugs_model), DynamicPPL.DefaultContext()
    )[2].logp
@test bugs_logp ≈ dppl_logp rtol = 1E-6
