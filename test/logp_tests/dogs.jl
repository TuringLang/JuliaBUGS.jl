bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].inits[1]

bugs_model = compile(bugs_model_def, data, inits)
vi = bugs_model.varinfo

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

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, false), DefaultContext())[2]

dppl_logp =
    DynamicPPL.evaluate!!(
        dppl_model, DynamicPPL.settrans!!(vi, false), DynamicPPL.DefaultContext()
    )[2].logp
@test bugs_logp ≈ -1243.188922 rtol = 1E-6 # reference value from ProbPALA
@test bugs_logp ≈ dppl_logp rtol = 1E-6

bugs_logp = JuliaBUGS.evaluate!!(JuliaBUGS.settrans(bugs_model, true), DefaultContext())[2]
dppl_logp =
    DynamicPPL.evaluate!!(
        dppl_model, get_params_varinfo(bugs_model), DynamicPPL.DefaultContext()
    )[2].logp
@test bugs_logp ≈ dppl_logp rtol = 1E-6
