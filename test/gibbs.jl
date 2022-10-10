using SymbolicPPL
using SymbolicPPL: SampleFromPrior
using StatsPlots
using MCMCChains

## Bayesian Linear regression: http://www.medicine.mcgill.ca/epidemiology/joseph/courses/epib-675/bayesreg.pdf
expr = bugsmodel"""
   for (i in 1:21) { # loop over cities 
      mu.dmf[i] <- alpha + beta*fl[i] # regression equation 
      dmf[i] ~ dnorm(mu.dmf[i],tau) # distribution individual values 
   } 
   alpha ~ dnorm(0.0,0.000001) # prior for intercept
   beta ~ dnorm(0.0,0.000001) # prior for slope
   sigma ~ dunif(0,400) # prior for residual SD
   tau <- 1/(sigma*sigma) # precision required by WinBUGS
   for (i in 1:21) {   # calculate residuals
      residual[i] <- dmf[i]- mu.dmf[i] 
   } 
   pred.mean.1.7 <- alpha + beta*1.7 # mean prediction for fl=1.7 
   pred.ind.1.7 ~ dnorm(pred.mean.1.7, tau) # individual pred for fl=1.7
"""
data = (dmf=[236,246,252,258,281,303,323,343,412,444,556,652, 673,703,706,722,733,772,810,823,1027],
fl=[1.9,2.6,1.8,1.2, 1.2,1.2,1.3,0.9,0.6,0.5,0.4,0.3,0.0,0.2,0.1,0.0,0.2,0.1, 0.0,0.1,0.1])
initials = (alpha=100,beta=0,sigma=100)
model = compile_graphppl(model_def=expr, data=data, initials=initials)

sampler = SampleFromPrior(model)
samples = AbstractMCMC.sample(model, sampler, 12000, discard_initial =2000);
plot(samples)
summarize(samples)
