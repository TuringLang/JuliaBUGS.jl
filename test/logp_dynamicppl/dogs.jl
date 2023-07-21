bugs_model_def = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].model_def
data = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].data
inits = JuliaBUGS.BUGSExamples.VOLUME_I[:dogs].inits[1]

bugs_model = compile(bugs_model_def, data, inits)

JuliaBUGS.get_params_varinfo(bugs_model)

@model function dogs(Dogs, Trials, y)
    alpha ~ RightTruncatedFlat(-0.00001)
    beta ~ RightTruncatedFlat(-0.00001)

    p = Matrix{Real}(undef, Dogs, Trials)
    for i in 1:Dogs
        p[i, 1] = 0
        for j in 2:Trials
            p[i, j] = exp(alpha * xa[i, j] + beta * xs[i, j])
        end
    end

    for i in 1:Dogs
        for j in 2:Trials
            y[i, j] ~ dbern(p[i, j])
        end
    end

    A = exp(alpha)
    B = exp(beta)

    return A, B
end

@unpack Dogs, Trials, Y = data
y = Matrix{Real}(undef, Dogs, Trials)
xa = Matrix{Real}(undef, Dogs, Trials)
xs = Matrix{Real}(undef, Dogs, Trials)
for i in 1:Dogs
    xa[i, 1] = 0
    xs[i, 1] = 0
    for j in 2:Trials
        xa[i, j] = sum(Y[i, 1:(j - 1)])
        xs[i, j] = j - 1 - xa[i, j]
        y[i, j] = 1 - Y[i, j]
    end
end
dppl_model = dogs(Dogs, Trials, y)

for t in [false, true]
    compare_dppl_bugs_logps(dppl_model, bugs_model, t)
end

# this currently broken
# at first glance, `y` is going to be sampled, but since I am using the `DefaultContext`, does it matter?
