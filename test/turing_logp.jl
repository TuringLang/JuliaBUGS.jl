using UnPack
using Graphs, MetaGraphsNext
using Bijectors
using Setfield, BangBang
using Distributions

using Turing, DynamicPPL
using JuliaBUGS

@model function translated_model(Y, x, xbar, N, T)
    var"alpha.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"alpha.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"beta.c" ~ JuliaBUGS.dnorm(0.0, 1.0E-6)
    var"beta.tau" ~ JuliaBUGS.dgamma(0.001, 0.001)
    var"tau.c" ~ JuliaBUGS.dgamma(0.001, 0.001)

    alpha = Vector{Real}(undef, N)
    beta = Vector{Real}(undef, N)
    mu = Matrix{Real}(undef, N, T)

    for i in 1:N
        alpha[i] ~ JuliaBUGS.dnorm(var"alpha.c", var"alpha.tau")
        beta[i] ~ JuliaBUGS.dnorm(var"beta.c", var"beta.tau")

        for j in 1:T
            mu[i, j] = alpha[i] + beta[i] * (x[j] - xbar)
            Y[i, j] ~ JuliaBUGS.dnorm(mu[i, j], var"tau.c")
        end
    end

    sigma = 1 / sqrt(var"tau.c")
    alpha0 = var"alpha.c" - xbar * var"beta.c"

    return alpha0, sigma
end


rats = JuliaBUGS.BUGSExamples.volume_i_examples[:rats];
@unpack Y, x, xbar, N, T = JuliaBUGS.BUGSExamples.volume_i_examples[:rats].data;

rats_model = translated_model(Y, x, xbar, N, T)

p = compile(rats.model_def, rats.data, rats.inits[1]);
vi = deepcopy(p.ℓ.re.prototype)
p.ℓ.re()

vi = DynamicPPL.resetlogp!!(vi)

getlogp(last(DynamicPPL.evaluate!!(rats_model, vi, DefaultContext())))

new_vi = pp.ℓ.re()
