bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].inits[1]

bugs_model = compile(bugs_model_def, data, inits)

@model function dogs(Dogs, Trials, Y, y)
    # Initialize matrices
    xa = zeros(Dogs, Trials)
    xs = zeros(Dogs, Trials)
    p = zeros(Dogs, Trials)

    # Flat priors for alpha and beta, restricted to (-∞, -0.00001)
    alpha ~ dunif(-10, -1.0e-5)
    beta ~ dunif(-10, -1.0e-5)

    for i in 1:Dogs
        xa[i, 1] = 0
        xs[i, 1] = 0
        p[i, 1] = 0

        for j in 2:Trials
            xa[i, j] = sum(Y[i, 1:(j - 1)])
            xs[i, j] = j - 1 - xa[i, j]
            p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
            # The Bernoulli likelihood
            y[i, j] ~ dbern(p[i, j])
        end
    end

    # Transformation to positive values
    A = exp(alpha)
    B = exp(beta)

    return A, B
end

@unpack Dogs, Trials, Y = data
dppl_model = dogs(Dogs, Trials, Y, 1 .- Y)

vi, bugs_logp = get_vi_logp(bugs_model, false)
# test if JuliaBUGS and DynamicPPL agree on parameters in the model
# @test params_in_dppl_model(dppl_model) == keys(vi)
vi = JuliaBUGS.get_params_varinfo(bugs_model, vi)

_, dppl_logp = get_vi_logp(dppl_model, vi, false)
@test bugs_logp ≈ -1243.188922 rtol = 1E-6 # reference value from ProbPALA
@test bugs_logp ≈ dppl_logp rtol = 1E-6

vi, bugs_logp = get_vi_logp(bugs_model, true)
vi, dppl_logp = get_vi_logp(dppl_model, vi, true)
@test bugs_logp ≈ dppl_logp rtol = 1E-6
