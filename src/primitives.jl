# TODO: make this a module and export the functions
# names(MODULE_NAME) can get all the functions defined in a module

using Distributions
using LogExpFunctions
import LogExpFunctions: logistic, logit, cloglog, cexpexp, log1pexp
using SpecialFunctions
import SpecialFunctions: gamma
using LinearAlgebra
import LinearAlgebra: logdet

const DISTRIBUTIONS = [:dgamma, :dnorm]

const INVERSE_LINK_FUNCTION =
    (logit = :logistic, cloglog = :cexpexp, log = :exp, probit = :phi)

""" 
    Distributions
"""
dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))
dbern(p) = Bernoulli(p)
dbin(p, n) = Binomial(n, p)
dcat(p) = Categorical(p)
dnegbin(p, r) = NegativeBinomial(r, p)
dpois(lambda) = Poisson(lambda)
dgeom(p) = Geometric(p)
# dgeom0(p) = Geometric(p)
# dhyper(n, m, N, psi) 

dneta(a, b) = Beta(a, b)
dchisqr(k) = Chisq(k)
ddexp(mu, tau) = DoubleExponential(mu, tau) # TODO: check if tau == θ
dexp(lambda) = Exponential(lambda) # TODO: check!
# dflat()
dgamma(alpha, beta) = Gamma(alpha, beta)
# dgev(mu, sigma, eta)
# df(n, m, mu, tau)
# dgamma(r, mu, beta)
# dgpar(mu, sigma, eta)

"""
    Functions
"""
phi(x) = Distributions.cdf(Normal, x)

arccos(x) = acos(x)
arccosh(x) = acosh(x)
arcsin(x) = asin(x)
arcsinh(x) = asinh(x)
arctan(x) = atan(x)
arctanh(x) = atanh(x)
icloglog(x) = cexpexp(x)
ilogit(x) = logistic(x)
logfact(x) = log(factorial(x))
loggram(x) = log(gamma(x))
softplus(x) = log1pexp(x)
step(x) = x > 1 ? 1 : 0

inprod(v1, v2) = LinearAlgebra.dot(v1, v2)
inverse(v) = inv(v)
