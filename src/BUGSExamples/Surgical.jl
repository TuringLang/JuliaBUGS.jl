using BugsModels
using StatsPlots
using MCMCChains

"""
Link: https://chjackson.github.io/openbugsdoc/Examples/Pumps.html
Status: 
Complier: Working
Sampler: Working
"""

simple_model = bugsmodel"""
    for( i in 1 : N ) {
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    }  
""" 

data = (n=[47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
r=[0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
N=12)
inits0 = (p = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], )
inits1 = (p = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], )

model = compile_graphppl(model_def=simple_model, data=data, initials=inits0)

sampler = SampleFromPrior(model)
samples = AbstractMCMC.sample(model, sampler, 11000, discard_initial=1000)
summarize(samples)

###################### Model with random effects ########################
# Sampler not working

realistic_model = bugsmodel"""
    for( i in 1 : N ) {
        b[i] ~ dnorm(mu,tau)
        r[i] ~ dbin(p[i],n[i])
        logit(p[i]) <- b[i]
    }
    pop.mean <- exp(mu) / (1 + exp(mu))
    mu ~ dnorm(0.0,1.0E-6)
    sigma <- 1 / sqrt(tau)
    tau ~ dgamma(0.001,0.001)   
"""

data = (n=[47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
r=[0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
N=12)
inits0 = (p = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], tau = 1, mu = 0)
inits1 = (p = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], tau = 0.1, mu = 1.0)

model = compile_graphppl(model_def=realistic_model, data=data, initials=inits1)

_, state = AbstractMCMC.step(Random.default_rng(), model, sampler) 
_, state = AbstractMCMC.step(Random.default_rng(), model, sampler, state) 

sampler = SampleFromPrior(model)
samples = AbstractMCMC.sample(model, sampler, 11000, discard_initial=1000);
plot(samples)
summarize(samples[namesingroup(samples, :p)])
