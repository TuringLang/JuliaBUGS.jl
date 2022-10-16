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

compile_inter(ex, (a=1, b=2))
g = compile(ex, (a=1, b=2))

model = toturing(g)
inspect_toturing(g)
rand(model())

##
ex = @bugsast begin
    a[1] ~ dnorm(0, 1)
    a[2] ~ dnorm(a[1], 1)
    a[3] ~ dnorm(a[2], a[1]^2)
end

compile_inter(ex, (a=[1, 2, missing], ))
g = compile(ex, (a=[1, 2, missing], ))

model = toturing(g)
inspect_toturing(g)
rand(model())

##
m = SymbolicPPL.BUGSExamples.EXAMPLES[:rats];
model = compile(m[:model_def], m[:data], m[:inits][1]);
turing_model = toturing(model);
sampler = MetropolisHastings(StaticProposal(Normal(0,1)))
chn = sample(turing_model(), MH(), 10000)