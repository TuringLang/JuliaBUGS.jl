name = "Beetles: choice of link function"

model_def = @bugs begin
    for i in 1:N
        r[i] ~ dbin(p[i], n[i])
        p[i] = logistic(alpha.star + beta * (x[i] - mean(x[:])))
        # p[i] = phi(alpha.star + beta * (x[i] - mean(x[:])))
        # p[i] = cexpexp(alpha.star + beta * (x[i] - mean(x[:])))
        rhat[i] = n[i] * p[i]
    end
    alpha = alpha.star - beta * mean(x[:])
    beta ~ dnorm(0.0, 0.001)
    alpha.star ~ dnorm(0.0, 0.001)
end

original = """
model {
    for( i in 1 : N ) {
        r[i] ~ dbin(p[i],n[i])
        logit(p[i]) <- alpha.star + beta * (x[i] - mean(x[]))
        # probit(p[i]) <- alpha.star + beta * (x[i] - mean(x[]))
        # cexpexp(p[i]) <- alpha.star + beta * (x[i] - mean(x[]))
        rhat[i] <- n[i] * p[i]
    }
    alpha <- alpha.star - beta * mean(x[])
    beta ~ dnorm(0.0,0.001)
    alpha.star ~ dnorm(0.0,0.001)
}
"""

data = (x = [1.6907, 1.7242, 1.7552, 1.7842, 1.8113, 1.8369, 1.8610, 1.8839],
    n = [59, 60, 62, 56, 63, 59, 62, 60],
    r = [6, 13, 18, 28, 52, 53, 61, 60], N = 8)

inits = (alpha.star = 0, beta = 0)
inits_alternative = (alpha.star = 1, beta = 1)

# logit/logistic
reference_results = (
    var"alpha" = (mean = -60.78, std = 5.168),
    var"beta" = (mean = 34.3, std = 2.904),
    var"rhat[1]" = (mean = 3.571, std = 0.957),
    var"rhat[2]" = (mean = 9.955, std = 1.691),
    var"rhat[3]" = (mean = 22.51, std = 2.115),
    var"rhat[4]" = (mean = 33.9, std = 1.768),
    var"rhat[5]" = (mean = 50.04, std = 1.655),
    var"rhat[6]" = (mean = 53.21, std = 1.108),
    var"rhat[7]" = (mean = 59.14, std = 0.7393),
    var"rhat[8]" = (mean = 58.68, std = 0.4284)
)
# probit/phi
# reference_results = (
#     var"alpha" = (mean = -35.08, std = 2.64),
#     var"beta" = (mean = 19.81, std = 1.485),
#     var"rhat[1]" = (mean = 3.429, std = 1.015),
#     var"rhat[2]" = (mean = 10.74, std = 1.701),
#     var"rhat[3]" = (mean = 23.47, std = 1.927),
#     var"rhat[4]" = (mean = 33.81, std = 1.623),
#     var"rhat[5]" = (mean = 49.61, std = 1.631),
#     var"rhat[6]" = (mean = 53.28, std = 1.153),
#     var"rhat[7]" = (mean = 59.61, std = 0.7393),
#     var"rhat[8]" = (mean = 59.18, std = 0.363)
# )
# cloglog/cexpexp
# reference_results = (
#     var"alpha" = (mean = -39.7, std = 3.197),
#     var"beta" = (mean = 22.11, std = 1.775),
#     var"rhat[1]" = (mean = 5.646, std = 1.113),
#     var"rhat[2]" = (mean = 11.31, std = 1.57),
#     var"rhat[3]" = (mean = 20.94, std = 1.874),
#     var"rhat[4]" = (mean = 30.34, std = 1.645),
#     var"rhat[5]" = (mean = 47.74, std = 1.712),
#     var"rhat[6]" = (mean = 54.07, std = 1.218),
#     var"rhat[7]" = (mean = 61.02, std = 0.5342),
#     var"rhat[8]" = (mean = 59.92, std = 0.1004)
# )

beetles = Example(
    name, model_def, original, data, inits, inits_alternative, reference_results)
