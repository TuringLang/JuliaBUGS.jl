# TODO: make this a module and export the functions
# names(MODULE_NAME) can get all the functions defined in a module

using Distributions
using LogExpFunctions
import LogExpFunctions: logistic, logit, cloglog, cexpexp, log1pexp
import Base: step
using SpecialFunctions
import SpecialFunctions: gamma
using LinearAlgebra
import LinearAlgebra: logdet
import AbstractPPL
using Symbolics
using IfElse
using Turing:Flat

const DISTRIBUTIONS = [:dgamma, :dnorm, :dbeta, :dbin, :dexp, :dpois, :dflat, :dunif, :dbern]

const INVERSE_LINK_FUNCTION =
    (logit = :logistic, cloglog = :cexpexp, log = :exp, probit = :phi)

# Reload `set_node_value!`, sampling a Binomial will give a Integer type, while GraphPPL
# only support Float right now, this is a work around
function AbstractPPL.GraphPPL.set_node_value!(m::AbstractPPL.GraphPPL.Model, ind::AbstractPPL.VarName, value::Integer)
    @assert typeof(m[ind].value[]) <: AbstractFloat
    m[ind].value[] = Float64(value)
end
    

""" 
    Distributions

For now, the function argument `check_args` has to be used to avoid support
checking, but some similar functionality should be provided to avoid sneaky
wrong results.
An alternative is directly use the underlying struct and basically write 
our own type and constructors.
"""
dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))
dbern(p) = Bernoulli(p)

dbin(p, n::Integer) = Binomial(n, p)
function dbin(p, n::AbstractFloat) 
    if isinteger(n)
        return Binomial(n, p)
    else
        error("Second argument of dbin has to be integer.")
    end
end

dcat(p) = Categorical(p)
dnegbin(p, r) = NegativeBinomial(r, p)
dpois(lambda) = Poisson(lambda)
dgeom(p) = Geometric(p)
dunif(a, b) = Uniform(a, b)
dflat() = Flat()

dbeta(a, b) = Beta(a, b, check_args=false)
dexp(lambda) = Exponential(1/lambda)
dgamma(r, mu) = Gamma(r, 1/mu, check_args=false) 

"""
    Functions
"""
phi(x) = Distributions.cdf(Normal(0, 1), x)

# If don't register dpois, Poisson(a::Num) will create a Poisson{Num} object, but we want the Poisson constructor 
# is the function expr instead of concrete types.
@register_symbolic dpois(lambda::Num)

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
step(x::Symbolics.Num) = IfElse.ifelse(x>1,1,0)

pow(base, exp) = base^exp
inprod(v1, v2) = LinearAlgebra.dot(v1, v2)
inverse(v) = inv(v)
