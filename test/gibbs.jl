using BugsModels

spl = GibbsSampler()

expr = bugsmodel"""
    for( i in 1 : N ) {
        p[i] ~ dbeta(1.0, 1.0)
        r[i] ~ dbin(p[i], n[i])
    }  
"""
data = (n = [47, 148, 119, 810,   211, 196, 148, 215, 207, 97, 256, 360],
r = [0, 18, 8, 46, 8, 13, 9,   31, 14, 8, 29, 24],
N = 12)
model = compile_graphppl(model_def = expr, data = data)

samples = AbstractMCMC.sample(model, spl, 4000);
summarize(samples)

##

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

data = (x = [8.0, 15.0, 22.0, 29.0, 36.0], xbar = 22, N = 30, T = 5, Y=permutedims(reshape(Y, 5, 30), (2, 1)))

model = compile_graphppl(model_def = expr, data = data);

@run sample, _ = AbstractMCMC.step(Random.default_rng(), model, spl)

## 
@time samples = AbstractMCMC.sample(model, spl, 10)
summarize(samples)