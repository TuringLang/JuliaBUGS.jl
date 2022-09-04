using BugsModels
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

sampler = SampleFromPrior(0, 0, getchildren(model))
samples = AbstractMCMC.sample(model, sampler, 12000, discard_initial =2000);
plot(samples)
summarize(samples)


## https://chjackson.github.io/openbugsdoc/Examples/Surgical.html -- simple model
expr = bugsmodel"""
    for( i in 1 : N ) {
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    }  
"""
data = (n=[47, 148, 119, 810, 211, 196, 148, 215, 207, 97, 256, 360],
   r=[0, 18, 8, 46, 8, 13, 9, 31, 14, 8, 29, 24],
   N=12)
initials = (p = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], )
model = compile_graphppl(model_def=expr, data=data, initials=initials)

sampler = SampleFromPrior(0, 0, getchildren(model))
samples = AbstractMCMC.sample(model, sampler, 10000);
plot(samples)
summarize(samples)

## https://chjackson.github.io/openbugsdoc/Examples/Pumps.html
expr = bugsmodel"""
   for (i in 1 : N) {
      theta[i] ~ dgamma(alpha, beta)
      lambda[i] <- theta[i] * t[i]
      x[i] ~ dpois(lambda[i])
   }
   
   alpha ~ dexp(1)
   beta ~ dgamma(0.1, 1.0)
"""

data = (t=[94.3, 15.7, 62.9, 126, 5.24, 31.4, 1.05, 1.05, 2.1, 10.5],
   x=[5, 1, 5, 14, 3, 19, 1, 1, 4, 22], N=10)
initials = (alpha=1, beta=1)
model = compile_graphppl(model_def=expr, data=data, initials=initials)

sampler = SampleFromPrior(getchildren(model))
samples = AbstractMCMC.sample(model, sampler, 100);
summarize(samples)
summarize(samples[namesingroup(samples, :x)])

## https://chjackson.github.io/openbugsdoc/Examples/Rats.html
# Results are wrong

expr = bugsmodel"""
   for( i in 1 : N ) {
      for( j in 1 : T ) {
         Y[i , j] ~ dnorm(mu[i , j],tau.c)
         mu[i , j] <- alpha[i] + beta[i] * (x[j] - xbar)
      }
      alpha[i] ~ dnorm(alpha.c,alpha.tau)
      beta[i] ~ dnorm(beta.c,beta.tau)
   }
   tau.c ~ dgamma(0.001,0.001)
   sigma <- 1 / sqrt(tau.c)
   alpha.c ~ dnorm(0.0,1.0E-6)   
   alpha.tau ~ dgamma(0.001,0.001)
   beta.c ~ dnorm(0.0,1.0E-6)
   beta.tau ~ dgamma(0.001,0.001)
   alpha0 <- alpha.c - xbar * beta.c   
"""

Y = [151, 199, 246, 283, 320,
   145, 199, 249, 293, 354,
   147, 214, 263, 312, 328,
   155, 200, 237, 272, 297,
   135, 188, 230, 280, 323,
   159, 210, 252, 298, 331,
   141, 189, 231, 275, 305,
   159, 201, 248, 297, 338,
   177, 236, 285, 350, 376,
   134, 182, 220, 260, 296,
   160, 208, 261, 313, 352,
   143, 188, 220, 273, 314,
   154, 200, 244, 289, 325,
   171, 221, 270, 326, 358,
   163, 216, 242, 281, 312,
   160, 207, 248, 288, 324,
   142, 187, 234, 280, 316,
   156, 203, 243, 283, 317,
   157, 212, 259, 307, 336,
   152, 203, 246, 286, 321,
   154, 205, 253, 298, 334,
   139, 190, 225, 267, 302,
   146, 191, 229, 272, 302,
   157, 211, 250, 285, 323,
   132, 185, 237, 286, 331,
   160, 207, 257, 303, 345,
   169, 216, 261, 295, 333,
   157, 205, 248, 289, 316,
   137, 180, 219, 258, 291,
   153, 200, 244, 286, 324]

data = (x=[8.0, 15.0, 22.0, 29.0, 36.0], xbar=22, N=30, T=5, Y=permutedims(reshape(Y, 5, 30), (2, 1)))

initials = (alpha = [250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250,
250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250],
beta = [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],         
var"alpha.c" = 150, var"beta.c" = 10,
var"tau.c" = 1, var"alpha.tau" = 1, var"beta.tau" = 1)

# initials = (alpha = [25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0,
# 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0, 25.0],
# beta = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6,
# 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6],         
# var"alpha.c" = 15, var"beta.c" = 1,
# var"tau.c" = 0.1, var"alpha.tau" = 0.1, var"beta.tau" = 0.1)

@time model = compile_graphppl(model_def=expr, data=data, initials=initials);
@code_warntype compile_graphppl(model_def=expr, data=data, initials=initials)

##
sampler = SampleFromPrior(model)
@time sample = AbstractMCMC.step(Random.default_rng(), model, sampler)

sampler = SampleFromPrior(model)
samples = AbstractMCMC.sample(model, sampler, 11000, discard_initial=1000)
samples = AbstractMCMC.sample(model, sampler, 11000, discard_initial=1000)
summarize(samples)
summarize(samples[[:alpha0, :sigma]])