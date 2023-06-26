bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].inits[1]

@unpack Dogs, Trials, Y = data

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

turing_model = dogs(Y, Dogs, Trials)

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