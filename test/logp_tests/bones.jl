bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:bones].inits[1]

bugs_model = compile(bugs_model_def, data, inits)

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

@unpack grade, nChild, nInd, ncat, gamma, delta = data
dppl_model = bones(grade, nChild, nInd, ncat, gamma, delta)

vi, bugs_logp = get_vi_logp(bugs_model, false)
params_vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
@test params_in_dppl_model(dppl_model) == keys(params_vi)

vi, dppl_logp = get_vi_logp(dppl_model, vi, false)
# ! ProbPALA compile error
@test bugs_logp ≈ dppl_logp rtol = 1E-6

vi, bugs_logp = get_vi_logp(bugs_model, true)
vi, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test bugs_logp ≈ dppl_logp rtol = 1E-6