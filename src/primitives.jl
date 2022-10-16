using Distributions
using LogExpFunctions
import LogExpFunctions: logistic, logit, cloglog, cexpexp, log1pexp
import Base: step
using SpecialFunctions
import SpecialFunctions: gamma
using LinearAlgebra
import LinearAlgebra: logdet
using AbstractPPL: VarName
using Statistics
import Statistics.mean
using IfElse
using MacroTools
using Symbolics

""" 
    NA

`NA` is alias for [`missing`](@ref).
"""
const NA = :missing

const DISTRIBUTIONS = [:truncated, :censored, :dgamma, :dnorm, :dbeta, :dbin, :dcat, :dexp, :dpois, :dflat, 
    :dunif, :dbern, :bar]

USER_DISTRIBUTIONS = []

const INVERSE_LINK_FUNCTION =
    (logit = :logistic, cloglog = :cexpexp, log = :exp, probit = :phi)

TRACED_FUNCTIONS = [:exp, ]

VECTOR_FUNCTION = [:dcat, ]

# # Reload `set_node_value!`, sampling a Binomial will give a Integer type, while GraphPPL
# # only support Float right now, this is a work around
# function set_node_value!(m::Model, ind::VarName, value::Integer)
#     @assert typeof(m[ind].value[]) <: AbstractFloat
#     m[ind].value[] = Float64(value)
# end

"""
    rreshape

Reshape the array `x` to the shape `dims`, row major order.
"""
rreshape(v::Vector, dim) = permutedims(reshape(v, reverse(dim)), length(dim):-1:1)    

""" 
    Univariate Distributions

Every distribution function is registered as a symbolic function and later defined using corresponding 
distribution in Distributions.jl. Symbolic registering stops function being evaluated at symbolic compilation
stage. 
"""

@register_symbolic dnorm(mu, tau) 
dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))

@register_symbolic dbern(p)
dbern(p) = Bernoulli(p)

@register_symbolic dbin(p, n)
function dbin(p, n::Float64) 
    @assert isinteger(n) "Second argument of `dbin` must be an integer"
    return Binomial(Integer(n), p)
end
dbin(p, n::Integer) = Binomial(n, p)

@register_symbolic dnegbin(p, r)
dnegbin(p, r) = NegativeBinomial(r, p)

@register_symbolic dpois(lambda)
dpois(lambda) = Poisson(lambda)

@register_symbolic dgeom(p)
dgeom(p) = Geometric(p)

@register_symbolic dunif(a, b)
dunif(a, b) = Uniform(a, b)

dflat() = DFlat()

@register_symbolic dbeta(alpha, beta)
dbeta(a, b) = Beta(a, b)

@register_symbolic dexp(lambda)
dexp(lambda) = Exponential(1/lambda)

@register_symbolic dgamma(alpha, beta)
dgamma(r, mu) = Gamma(r, 1/mu) 

@register_symbolic dweib(v, λ)
dweib(v, λ) = Weibull(v, 1/λ)

"""
    Multivariate Distributions
"""

@register_symbolic dcat(p::Vector)
dcat(p) = Categorical(p/sum(p))

""" 
    Truncated and Censored Functions
"""

@register_symbolic censored(d, l, u)
@register_symbolic censored_with_lower(d, l)
@register_symbolic censored_with_upper(d, u)
censored_with_lower(d, l) = Distributions.censored(d; lower = l)
censored_with_upper(d, u) = Distributions.censored(d; upper = u)

@register_symbolic truncated(d, l, u)
@register_symbolic truncated_with_lower(d, l)
@register_symbolic truncated_with_upper(d, u)
truncated_with_lower(d, l) = Distributions.truncated(d; lower = l)
truncated_with_upper(d, u) = Distributions.truncated(d; upper = u)

"""
    Functions
"""
phi(x) = Distributions.cdf(Normal(0, 1), x)

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
step(x::Num) = IfElse.ifelse(x>1,1,0)

pow(base, exp) = base^exp
@register_symbolic inverse(v::Vector)
inverse(v) = inv(v)

Statistics.mean(v::Symbolics.Arr{Num, 1}) = mean(Symbolics.scalarize(v))
sd(v::Symbolics.Arr{Num, 1}) = Statistics.std(Symbolics.scalarize(v))
inprod(a::Array, b::Array) = a*b

# dummy function used for testing -- do not use
@register_symbolic foo(v::Array)
foo(v) = sum(v)
@register_symbolic bar(v::Array)
bar(v) = dcat(reduce(vcat, v))

# TODO: add name collision check
"""
    @primitive

Macro to define a function that can be used in BUGS model. 
!!! warning
    User should be cautious when using this macro, we recommend only use this macro for pure functions that do common 
    mathematical operations.
"""
macro primitive(ex, isdistribution = false)
    def = MacroTools.splitdef(ex)
    reg_sym = Expr(:macrocall, Symbol("@register_symbolic"), LineNumberNode(@__LINE__, @__FILE__), Expr(:call, def[:name], def[:args]...))
    eval(reg_sym)
    eval(ex)
    isdistribution && push!(USER_DISTRIBUTIONS, def[:name])
    return nothing
end