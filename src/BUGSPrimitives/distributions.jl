export dnorm,
    dlogis,
    dt,
    ddexp,
    dflat,
    dexp,
    dgamma,
    dchisqr,
    dweib,
    dlnorm,
    dggamma,
    dpar,
    dgev,
    dgpar,
    df,
    dunif,
    dbeta,
    dmnorm,
    dmt,
    dwish,
    ddirich,
    # Discrete distributions
    dbern,
    dbin,
    dcat,
    dpois,
    dgeom,
    dnegbin,
    dbetabin,
    dhyper,
    dmulti

DISTRIBUTIONS = [
    :dnorm,
    :dlogis,
    :dt,
    :ddexp,
    :dflat,
    :dexp,
    :dgamma,
    :dchisqr,
    :dweib,
    :dlnorm,
    :dggamma,
    :dpar,
    :dgev,
    :dgpar,
    :df,
    :dunif,
    :dbeta,
    :dmnorm,
    :dmt,
    :dwish,
    :ddirich,
    :dbern,
    :dbin,
    :dcat,
    :dpois,
    :dgeom,
    :dnegbin,
    :dbetabin,
    :dhyper,
    :dmulti
]
export DISTRIBUTIONS
# Support for distributions that are part of BUGS but not implemented in Distributions.jl.

# Modified from https://github.com/TuringLang/Turing.jl/blob/master/src/stdlib/distributions.jl
# Rename `Flat` to `DFlat` to avoid name conflict with Turing.jl
"""
    Flat

The *flat distribution* is the improper distribution of real numbers that has the improper
probability density function
```math
f(x) = 1.
```
"""
struct DFlat <: ContinuousUnivariateDistribution end

Base.minimum(::DFlat) = -Inf
Base.maximum(::DFlat) = Inf

Base.rand(rng::Random.AbstractRNG, d::DFlat) = rand(Uniform(-100, 100))
Distributions.logpdf(::DFlat, x::Real) = zero(x)
Distributions.pdf(d::DFlat, x::Real) = exp(logpdf(d, x))
Distributions.cdf(d::DFlat, x::Real) = 0

# For vec support
Distributions.logpdf(::DFlat, x::AbstractVector{<:Real}) = zero(x)
Distributions.loglikelihood(::DFlat, x::AbstractVector{<:Real}) = zero(eltype(x))

"""
    LeftTruncatedFlat

Left truncated version of the flat distribution.
"""
struct LeftTruncatedFlat{T<:Real} <: ContinuousUnivariateDistribution
    l::T
end

Base.minimum(d::LeftTruncatedFlat) = d.l
Base.maximum(d::LeftTruncatedFlat) = Inf

Base.rand(rng::Random.AbstractRNG, d::LeftTruncatedFlat) = rand(rng) + d.l
function Distributions.logpdf(d::LeftTruncatedFlat, x::Real)
    z = float(zero(x))
    return x <= d.l ? oftype(z, -Inf) : z
end
Distributions.pdf(d::LeftTruncatedFlat, x::Real) = exp(logpdf(d, x))
Distributions.cdf(d::LeftTruncatedFlat, x::Real) = 0

# For vec support
function Distributions.loglikelihood(d::LeftTruncatedFlat, x::AbstractVector{<:Real})
    lower = d.l
    T = float(eltype(x))
    return any(xi <= lower for xi in x) ? T(-Inf) : zero(T)
end

"""
    RightTruncatedFlat

Right truncated version of the flat distribution.
"""
struct RightTruncatedFlat{T<:Real} <: ContinuousUnivariateDistribution
    r::T
end

Base.minimum(d::RightTruncatedFlat) = -Inf
Base.maximum(d::RightTruncatedFlat) = d.r

Base.rand(rng::Random.AbstractRNG, d::RightTruncatedFlat) = -rand(rng) + d.r
function Distributions.logpdf(d::RightTruncatedFlat, x::Real)
    z = float(zero(x))
    return x >= d.r ? oftype(z, Inf) : z
end
Distributions.pdf(d::RightTruncatedFlat, x::Real) = exp(logpdf(d, x))
Distributions.cdf(d::RightTruncatedFlat, x::Real) = 0

# For vec support
function Distributions.loglikelihood(d::RightTruncatedFlat, x::AbstractVector{<:Real})
    upper = d.r
    T = float(eltype(x))
    return any(xi >= upper for xi in x) ? T(Inf) : zero(T)
end

function truncated(d::DFlat, l::Real, r::Real)
    if l > r
        throw(ArgumentError("invalid truncation interval: $l > $r"))
    end
    return Uniform(l, r)
end

function truncated(d::DFlat, l::Real, ::Nothing)
    return LeftTruncatedFlat(l)
end

function truncated(d::DFlat, ::Nothing, r::Real)
    return RightTruncatedFlat(r)
end

### 
### Distributions
### 

###
### Continuous univariate, unrestricted range
### 

dnorm(mu, tau) = Normal(mu, 1 / sqrt(tau))

dlogis(μ, τ) = Logistic(μ, 1 / τ)

function dt(μ, τ, k)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for Student's t distribution.")
    end
    return TDist(k)
end

ddexp(μ, τ) = Laplace(μ, 1 / τ)

dflat() = DFlat()

###
### Continuous univariate, restricted to be positive
###
dexp(λ) = Exponential(1 / λ)

dgamma(a, b) = Gamma(a, 1 / b)

dchisqr(k) = Chisq(k)

dweib(a, b) = Weibull(a, 1 / b)

dlnorm(μ, τ) = LogNormal(μ, 1 / τ)

function var"gen.gamma"(a, b, c)
    if c != 1
        error("Only c = 1 is supported for generalized gamma distribution.")
    end
    return Gamma(a, 1 / b)
end
dggamma(a, b, c) = var"gen.gamma"(a, b, c)

dpar(a, b) = Pareto(a, b)

dgev(μ, σ, η) = GeneralizedExtremeValue(μ, σ, η)

dgpar(μ, σ, η) = GeneralizedPareto(μ, σ, η)

function df(n, m, μ, τ)
    if μ != 1 || τ != 1
        error("Only μ = 1 and τ = 1 are supported for F distribution.")
    end
    return FDist(n, m)
end

###
### Continuous univariate, restricted to a finite interval
###

dunif(a, b) = Uniform(a, b)

dbeta(a, b) = Beta(a, b)

###
### Continuous multivariate distributions
###

dmnorm(μ::Vector, T::Matrix) = MvNormal(μ, T)

dmt(μ::Vector, T::Matrix, k) = MvTDist(k, μ, T)

dwish(R::Matrix, k) = Wishart(k, R^(-1))

ddirich(θ::Vector) = Dirichlet(θ)

###
### Discrete univariate distributions
###

dbern(p) = Bernoulli(p)

dbin(p, n) = Binomial(n, p)

dcat(p) = Categorical(p)

dpois(θ) = Poisson(θ)

dgeom(θ) = Geometric(θ)

dnegbin(p, r) = NegativeBinomial(r, p)

dbetabin(a, b, n) = BetaBinomial(n, a, b)

function dhyper(n1, n2, m1, ψ)
    if ψ != 1
        error("Only ψ = 1 is supported for hypergeometric distribution.")
    end
    return Hypergeometric(n1, n2, m1)
end

###
### Discrete multivariate distributions
###

dmulti(θ::Vector, n) = Multinomial(n, θ)
