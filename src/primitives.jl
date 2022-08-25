using Distributions
using LogExpFunctions
import LogExpFunctions: logistic, logit, cloglog, cexpexp, log1pexp
using SpecialFunctions
import SpecialFunctions: gamma
using LinearAlgebra
import LinearAlgebra: logdet

const DISTRIBUTIONS = [:dgamma, :dnorm, ]
# <unary_function_name> ::= ABS | ARCCOS| ARCCOSH | ARCSIN | ARCSINH | ARCTAN |
#   ARCTANH | CLOGLOG | COS | COSH|  EXP | ICLOGLOG | ILOGIT | LOG |  LOGFACT |
#   LOGGAM | LOGIT | PHI | ROUND | SIN | SINH | SOFTPLUS | SQRT | STEP | TAN | TANH | TRUNC
const UNARY_FUNCTION_NAMES = [
    "abs", "arccos", "arccosh", "arcsin", "arcsinh", "arctan", "arctanh", "cloglog", "cos",
    "cosh", "exp", "icloglog", "ilogit", "log", "logfact", "loggam", "logit", "phi", "round",
    "sin", "sinh", "softplus", "sqrt", "step", "tan", "tanh", "trunc"
]
# <binary_function_name> ::= EQUALS | MAX | MIN | POWER
const BINARY_FUNCTION_NAMES = ["equals", "max", "min", "power"]

# <link_function> ::= CLOGLOG | LOG | LOGIT | PROBIT
const LINK_FUNCTION_NAMES = ["cloglog", "log", "logit", "probit"]

""" 
    Distributions
"""
dgamma(alpha, beta) = Gamma(alpha, beta)
dnorm(mu, tau) = Normal(mu, 1/sqrt(tau)) 

"""
    Functions
"""
INVERSE_LINK_FUNCTION = Dict(:logit => :logistic, :cloglog => :cexpexp, :log => exp, :probit => :phi)
phi(x) = Distributions.cdf(Normal, x)
arccos(x) = acos(x) # or arccos = acos
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


