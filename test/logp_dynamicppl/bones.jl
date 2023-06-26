bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].inits[1]

@unpack grade, nChild, nInd, ncat, gamma, delta = data

@model function bones(grade, nChild, nInd, ncat, gamma, delta)
    theta = Vector{Real}(undef, nChild)
    Q = Array{Real}(undef, nChild, nInd, maximum(ncat))
    p = Array{Real}(undef, nChild, nInd, maximum(ncat))
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

turing_model = bones(grade, nChild, nInd, ncat, gamma, delta)

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