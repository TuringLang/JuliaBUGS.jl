# TODO: the distributions and functions should be made into a separate module. 
# TODO: then a macro similar to `register_function` can be used to import all the functions. 
# TODO: import all Distributions distribution functions.
# TODO: test the functions and distributions against WinBUGS: construct model and use random generated data to test the interface.

const DISTRIBUTIONS = [
    :truncated,
    :censored,
    :dgamma,
    :dnorm,
    :dbeta,
    :dbin,
    :dcat,
    :dexp,
    :dpois,
    :dflat,
    :dunif,
    :dbern,
    :bar,
    :dmnorm,
    :ddirich,
    :dwish,
    :dmt,
]

USER_DISTRIBUTIONS = []

const INVERSE_LINK_FUNCTION = (logit=:logistic, cloglog=:cexpexp, log=:exp, probit=:phi)

TRACED_FUNCTIONS = [:exp]

""" 
    NA

`NA` is alias for [`missing`](@ref).
"""
const NA = missing

"""
    rreshape

Reshape the array `x` to the shape `dims`, row major order.
"""
rreshape(v::Vector, dim) = permutedims(reshape(v, reverse(dim)), length(dim):-1:1)

@register_symbolic _getindex(x, idx1)
@register_symbolic _getindex(x::Array, idx1) false
@register_symbolic _getindex(x::Array, idx1::Colon) false
@register_symbolic _getindex(x::Array, idx1, idx2) false
@register_symbolic _getindex(x::Array, idx1::Colon, idx2) false
@register_symbolic _getindex(x::Array, idx1, idx2::Colon) false
@register_symbolic _getindex(x::Array, idx1, idx2, idx3) false
@register_symbolic _getindex(x::Array, idx1::Colon, idx2, idx3) false
@register_symbolic _getindex(x::Array, idx1, idx2::Colon, idx3) false
@register_symbolic _getindex(x::Array, idx1, idx2, idx3::Colon) false
@register_symbolic _getindex(x::Array, idx1::Colon, idx2::Colon, idx3) false
@register_symbolic _getindex(x::Array, idx1, idx2::Colon, idx3::Colon) false
@register_symbolic _getindex(x::Array, idx1::Colon, idx2, idx3::Colon) false
# @register_symbolic _getindex(x::Array, idx1, idx2, idx3, idx4)
_getindex(x, i...) = x[i...]

###
### Standard functions
###

# abs
# cloglog: from LogExpFunctions
# cos
equals(x, y) = x == y ? 1 : 0
@register_symbolic equals(x, y)
# exp
inprod(a, b) = a * b
inverse(v) = LinearAlgebra.inv(v);
@register_symbolic inverse(v::Array);
# log
logdet(v) = LinearAlgebra.logdet(v)
logfact(x) = log(factorial(x))
loggam(x) = loggamma(x)
# logit: from LogExpFunctions
icloglog(x) = cexpexp(x)
ilogit(x) = logistic(x)
# max
Statistics.mean(v::Symbolics.Arr{Num,1}) = Statistics.mean(Symbolics.scalarize(v)) #; mean: from Statistics
# min
phi(x) = Distributions.cdf(Normal(0, 1), x)
pow(a, b) = a^b
# probit: from LogExpFunctions
# sqrt
rank(v::Vector, i::Int) = sortperm(v)[i];
@register_symbolic rank(v::Array, i::Int);
ranked(v::Vector, i::Int) = v[sortperm(v)[i]];
@register_symbolic ranked(v::Array, i::Int);
# round
sd(v::Vector) = Statistics.std(v);
sd(v::Symbolics.Arr{Num,1}) = Statistics.std(Symbolics.scalarize(v));
softplus(x) = log1pexp(x)
sort(v::Vector) = Base.sort(v);
@register_symbolic sort(v::Array);
step(x) = ifelse(x > 0, 1, 0);
step(x::Num) = IfElse.ifelse(x > 1, 1, 0);
sum(x::Symbolics.Arr) = Base.sum(Symbolics.scalarize(x))
# trunc

###
### Trigonometric functions
###

# sin
arcsin(x) = asin(x)
arcsinh(x) = asinh(x)
# cos
arccos(x) = acos(x)
arccosh(x) = acosh(x)
# tan
arctan(x) = atan(x)
arctanh(x) = atanh(x)

###
### Matrix Algebra
###

t(v::Vector) = v'
mexp(v::Matrix) = exp(v)
var"eigen.vals"(v::Matrix) = eigen(v).values

### 
### Model Checking
###

# replicate.post, replicate.prior, post.p.value, prior.p.value are not implemented, use facilities from MCMCChains instead

### 
### Functionals and differential equations
###

# Better support in the future, use packages from SciML
# `F(x)` LHS syntax not supported 

### 
### Distributions
### 

###
### Continuous univariate, unrestricted range
### 

@register_symbolic dnorm(mu, tau)
dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))

@register_symbolic dlogis(mu, tau)
dlogis(μ, τ) = Logistic(μ, 1 / τ)

@register_symbolic dt(μ, τ, k)
function dt(μ, τ, k)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for Student's t distribution.")
    end
    return TDist(k)
end

@register_symbolic ddexp(μ, τ)
ddexp(μ, τ) = Laplace(μ, 1 / τ)

dflat() = DFlat()

###
### Continuous univariate, restricted to be positive
###
@register_symbolic dexp(λ)
dexp(λ) = Exponential(1 / λ)

@register_symbolic dgamma(a, b)
dgamma(a, b) = Gamma(a, 1 / b)

@register dchisqr(k)
dchisqr(k) = Chisq(k)

@register_symbolic dweib(a, b)
dweib(a, b) = Weibull(a, 1 / b)

@register_symbolic dlnorm(μ, τ)
dlnorm(μ, τ) = LogNormal(μ, 1 / τ)

@register_symbolic var"gen.gamma"(a, b, c)
@register_symbolic dggamma(a, b, c)
function var"gen.gamma"(a, b, c)
    if c != 1
        error("Only c = 1 is supported for generalized gamma distribution.")
    end
    return Gamma(a, 1 / b)
end
dggamma(a, b, c) = var"gen.gamma"(a, b, c)

@register_symbolic dpar(a, b)
dpar(a, b) = Pareto(a, b)

@register_symbolic dgev(μ, σ, η)
dgev(μ, σ, η) = GeneralizedExtremeValue(μ, σ, η)

@register_symbolic dgpar(μ, σ, η)
dgpar(μ, σ, η) = GeneralizedPareto(μ, σ, η)

@register_symbolic df(n, m, μ, τ)
function df(n, m, μ, τ)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for F distribution.")
    end
    return FDist(n, m)
end

###
### Continuous univariate, restricted to a finite interval
###

@register_symbolic dunif(a, b)
dunif(a, b) = Uniform(a, b)

@register_symbolic dbeta(alpha, beta)
dbeta(a, b) = Beta(a, b)

###
### Continuous multivariate distributions
###

@register_symbolic dmnorm(μ::Vector, T::Matrix)
dmnorm(μ::Vector, T::Matrix) = MvNormal(μ, T)

@register_symbolic dmt(μ::Vector, T::Matrix, k)
dmt(μ::Vector, T::Matrix, k) = MvTDist(k, μ, T)

@register_symbolic dwish(R::Matrix, k)
dwish(R::Matrix, k) = Wishart(k, R^(-1))

@register_symbolic ddirich(θ::Vector)
ddirich(θ::Vector) = Dirichlet(θ)

###
### Discrete univariate distributions
###

@register_symbolic dbern(p)
dbern(p) = Bernoulli(p)

@register_symbolic dbin(p, n)
dbin(p, n) = Binomial(n, p)

# TODO: need to also register a scalar verison, in case p is a traced function call
@register_symbolic dcat(p)
@register_symbolic dcat(p::Vector) false
dcat(p) = Categorical(p)

@register_symbolic dpois(θ)
dpois(θ) = Poisson(θ)

@register_symbolic dgeom(θ)
dgeom(θ) = Geometric(θ)

@register_symbolic dnegbin(p, r)
dnegbin(p, r) = NegativeBinomial(r, p)

@register_symbolic dbetabin(a, b, n)
dbetabin(a, b, n) = BetaBinomial(n, a, b)

@register_symbolic dhyper(n1, n2, m1, ψ)
function dhyp(n1, n2, m1, ψ)
    if ψ != 1
        error("Only ψ = 1 is supported for hypergeometric distribution.")
    end
    return Hypergeometric(n1, n2, m1)
end

###
### Discrete multivariate distributions
###

@register_symbolic dmulti(θ::Vector, n)
dmulti(θ::Vector, n) = Multinomial(n, θ)

""" 
    Truncated and Censored Functions
"""

@register_symbolic censored(d, l, u)
@register_symbolic censored_with_lower(d, l)
@register_symbolic censored_with_upper(d, u)
censored_with_lower(d, l) = Distributions.censored(d; lower=l)
censored_with_upper(d, u) = Distributions.censored(d; upper=u)

@register_symbolic truncated(d, l, u)
@register_symbolic truncated_with_lower(d, l)
@register_symbolic truncated_with_upper(d, u)
truncated_with_lower(d, l) = Distributions.truncated(d; lower=l)
truncated_with_upper(d, u) = Distributions.truncated(d; upper=u)

USER_FUNCTIONS = []

"""
    @register_function

Macro to define a function that can be used in BUGS model. 
!!! warning
    User should be cautious when using this macro, we recommend only use this macro for pure functions that do common 
    mathematical operations.

```@repl
@register_function f(x) = x^2
SymbolicPPL.f(2)
```
"""
macro register_function(ex)
    push!(USER_FUNCTIONS, MacroTools.splitdef(ex)[:name])
    eval_registration(ex)
    return nothing
end

"""
    @register_function

Macro to define a distribution that can be used in BUGS model. 

```@repl
@register_function d(x) = Normal(0, x^2)
SymbolicPPL.d(1)
```
"""
macro register_distribution(ex)
    dist_name = eval_registration(ex)
    push!(USER_DISTRIBUTIONS, dist_name)
    return nothing
end

function eval_registration(ex)
    def = MacroTools.splitdef(ex)
    reg_sym = Expr(
        :macrocall,
        Symbol("@register_symbolic"),
        LineNumberNode(@__LINE__, @__FILE__),
        Expr(:call, def[:name], def[:args]...),
    )
    eval(reg_sym)
    eval(ex)
    return def[:name]
end
