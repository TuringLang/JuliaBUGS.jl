using Random
using SymbolicPPL
using Distributions
using AbstractMCMC
using MCMCChains
using AdvancedMH
using Turing

##
ex = @bugsast begin
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
    c ~ dnorm(b, a^2)
end 

g = compile(ex, (a=1, b=2), :DynamicPPL)
rand(model())

##
ex = @bugsast begin
    a[1] ~ dnorm(0, 1)
    a[2] ~ dnorm(a[1], 1)
    a[3] ~ dnorm(a[2], a[1]^2)
end

g = compile(ex, (a=[1, 2, missing],), :DynamicPPL)
rand(model())

## 
model_def = @bugsast begin
    for i in 1:N
        r[i] ~ dbin(p[i],n[i])
        b[i] ~ dnorm(0.0,tau)
        @link_function logit p[i] = alpha0 + alpha1 * x1[i] + alpha2 * x2[i] + alpha12 * x1[i] * x2[i] + b[i]
    end
    alpha0 ~ dnorm(0.0,1.0E-6)
    alpha1 ~ dnorm(0.0,1.0E-6)
    alpha2 ~ dnorm(0.0,1.0E-6)
    alpha12 ~ dnorm(0.0,1.0E-6)
    tau ~ dgamma(0.001,0.001)
    sigma = 1 / sqrt(tau)
end

data = (
    r = [10, 23, 23, 26, 17, 5, 53, 55, 32, 46, 10, 8, 10, 8, 23, 0, 3, 22, 15, 32, 3],
    n = [39, 62, 81, 51, 39, 6, 74, 72, 51, 79, 13, 16, 30, 28, 45, 4, 12, 41, 30, 51, 7],
    x1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    x2 = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    N = 21,
)

model = compile(model_def, data, :DynamicPPL); 
g = compile(model_def, data, :Graph); 
model = SymbolicPPL.todppl(g)

rand(model())
typeof(model())

using Turing
s = sample(model(), HMC(0.1, 5), 100000)

using StatsPlots
plot(s)

s[[:alpha0, :alpha1, :alpha12, :alpha2, :tau]]
# TODO: add variable tracking