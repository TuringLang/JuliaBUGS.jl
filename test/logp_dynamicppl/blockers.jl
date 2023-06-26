bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:blockers].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:blockers].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:blockers].inits[1]

@unpack rt, nt, rc, nc, Num = data

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

turing_model = blockers(rc, rt, nc, nt, Num)

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
    evaluate!!(DynamicPPL.settrans!!(bugs_model, false), JuliaBUGS.DefaultContext())
)

turing_logp_with_trans = getlogp(
    last(
        DynamicPPL.evaluate!!(
            turing_model, DynamicPPL.settrans!!(vi, true), DynamicPPL.DefaultContext()
        ),
    ),
)

julia_bugs_logp_with_trans = getlogp(
    evaluate!!(DynamicPPL.settrans!!(bugs_model, true), JuliaBUGS.DefaultContext())
)

@test turing_logp_no_trans ≈ bugs_logp_no_trans atol = 1e-6
@test turing_logp_with_trans ≈ julia_bugs_logp_with_trans atol = 1e-6