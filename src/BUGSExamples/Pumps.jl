using SymbolicPPL
using SymbolicPPL: SampleFromPrior
using MCMCChains
using MCMCChains: summarize

"""
Link: https://chjackson.github.io/openbugsdoc/Examples/Pumps.html
"""

model_def = bugsmodel"""
   for (i in 1 : N) {
      theta[i] ~ dgamma(alpha, beta)
      lambda[i] <- theta[i] * t[i]
      x[i] ~ dpois(lambda[i])
   }
   
   alpha ~ dexp(1)
   beta ~ dgamma(0.1, 1.0)
"""

data = (
    t = [94.3, 15.7, 62.9, 126, 5.24, 31.4, 1.05, 1.05, 2.1, 10.5],
    x = [5, 1, 5, 14, 3, 19, 1, 1, 4, 22],
    N = 10,
)
inits0 = (alpha = 1, beta = 1)

inits1 = (alpha = 10, beta = 10)

model = compile_graphppl(model_def = model_def, data = data, initials = inits0)

# Inference
sampler = BugsModels.SampleFromPrior(model);
samples = AbstractMCMC.sample(model, sampler, 11000, discard_initial = 1000);
summarize(samples[[namesingroup(samples, :theta)..., :alpha, :beta]])
