bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].inits[1]

bugs_model = compile(bugs_model_def, data, inits)

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
            xa[i, j] = sum(Y[i, 1:(j - 1)])
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

@unpack Dogs, Trials, Y = data
dppl_model = dogs(Y, Dogs, Trials)

for t in [true, false]
    compare_dppl_bugs_logps(dppl_model, bugs_model, t)
end

# this currently broken
# at first glance, `y` is going to be sampled, but since I am using the `DefaultContext`, does it matter?
