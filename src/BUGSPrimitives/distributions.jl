"""
    dnorm(μ=0, τ=1)

Return a Normal distribution object with mean `μ` and precision `τ` (the reciprocal of variance).

The mathematical form of the PDF for a Normal distribution in WinBUGS is given by:

\[
f(x|μ,τ) = \sqrt{\frac{τ}{2π}} e^{-τ \frac{(x-μ)^2}{2}}
\]

In Julia, this function uses mean `μ` and standard deviation `σ = \sqrt{1 / τ}`.
"""
function dnorm(μ=0, τ=1)
    σ = √(1 / τ)
    return Normal(μ, σ)
end

"""
    dlogis(μ, τ)

Return a Logistic distribution object with location `μ` and scale `s = 1 / √τ`.

The mathematical form of the PDF for a Logistic distribution in WinBUGS is given by:

\[
f(x|μ,τ) = \frac{√τ e^{-√τ(x-μ)}}{(1+e^{-√τ(x-μ)})^2}
\]
"""
function dlogis(μ, τ)
    s = 1 / √τ
    return Logistic(μ, s)
end

"""
    dt(μ, τ, k)

Return a Student's t distribution object with `ν` degrees of freedom, location `μ`, and scale `σ`.

The mathematical form of the PDF for a Student's t distribution in WinBUGS is given by:

\[
f(x|ν,μ,σ) = \frac{Γ((ν+1)/2)}{Γ(ν/2)√{νπ}σ}
\left(1+\frac{1}{ν}\left(\frac{x-μ}{σ}\right)^2\right)^{-\frac{ν+1}{2}}
\]

Only `pdf` and `logpdf` are implemented for this distribution.
"""
function dt(μ, τ, k)
    return TDistShiftedScaled(k, μ, √(1 / τ))
end

struct TDistShiftedScaled <: ContinuousUnivariateDistribution
    ν::Real
    μ::Real
    σ::Real

    TDistShiftedScaled(ν::Real, μ::Real, σ::Real) = new(ν, μ, σ)
end

Distributions.pdf(d::TDistShiftedScaled, x::Real) = pdf(TDist(d.ν), (x - d.μ) / d.σ) / d.σ
Distributions.logpdf(d::TDistShiftedScaled, x::Real) = logpdf(TDist(d.ν), (x - d.μ) / d.σ) - log(d.σ)

"""
    ddexp(μ, τ)

Return a Laplace (Double Exponential) distribution object with location `μ` and scale `b = 1 / √τ`.

The mathematical form of the PDF for a Laplace distribution in WinBUGS is given by:

\[
f(x|μ,τ) = \frac{√τ}{2} e^{-√τ |x-μ|}
\]
"""
function ddexp(μ, τ)
    b = 1 / √τ
    return Laplace(μ, b)
end

"""
FlatPrior()

A distribution type representing a flat (uniform) prior over the real line. This is not a valid
probability distribution, but can be used to represent a non-informative prior in Bayesian statistics.
The cdf, logcdf, quantile, cquantile, rand, and rand methods are not implemented
for this distribution, as they don't have meaningful definitions in the context of a flat prior.
When use in a model, the parameters always need to be initialized to a valid value.
"""
dflat() = Flat()

struct Flat <: ContinuousUnivariateDistribution
end

Distributions.minimum(::FlatPrior) = -Inf
Distributions.maximum(::FlatPrior) = Inf

Distributions.pdf(::FlatPrior, x::Real) = 1.0
Distributions.logpdf(::FlatPrior, x::Real) = 0.0

Distributions.cdf(::FlatPrior, x::Real) = throw(NotImplementedError())
Distributions.logcdf(::FlatPrior, x::Real) = throw(NotImplementedError())

Distributions.quantile(::FlatPrior, q::Real) = throw(NotImplementedError())
Distributions.cquantile(::FlatPrior, q::Real) = throw(NotImplementedError())

Distributions.rand(::FlatPrior) = throw(NotImplementedError())
Distributions.rand(::FlatPrior, n::Int) = throw(NotImplementedError())

struct LeftTruncatedFlat <: ContinuousUnivariateDistribution
    a::Real
end

Distributions.minimum(d::LeftTruncatedFlat) = d.a
Distributions.maximum(::LeftTruncatedFlat) = Inf

Distributions.pdf(d::LeftTruncatedFlat, x::Real) = x >= d.a ? 1.0 : 0.0
Distributions.logpdf(d::LeftTruncatedFlat, x::Real) = x >= d.a ? 0.0 : -Inf

struct RightTruncatedFlat <: ContinuousUnivariateDistribution
    b::Real
end

Distributions.minimum(::RightTruncatedFlat) = -Inf
Distributions.maximum(d::RightTruncatedFlat) = d.b

Distributions.pdf(d::RightTruncatedFlat, x::Real) = x <= d.b ? 1.0 : 0.0
Distributions.logpdf(d::RightTruncatedFlat, x::Real) = x <= d.b ? 0.0 : -Inf

"""
    TruncatedFlat

Truncated version of the flat distribution.
"""
struct TruncatedFlat <: ContinuousUnivariateDistribution
    a::Real
    b::Real

    TruncatedFlat(a::Real, b::Real) = (a < b) ? new(a, b) : throw(DomainError((a, b), "Requires a < b"))
end

Distributions.minimum(d::TruncatedFlat) = d.a
Distributions.maximum(d::TruncatedFlat) = d.b

Distributions.pdf(d::TruncatedFlat, x::Real) = (d.a <= x <= d.b) ? 1.0/(d.b - d.a) : 0.0
Distributions.logpdf(d::TruncatedFlat, x::Real) = log(pdf(d, x))

function truncated(::Flat, l::Real, r::Real)
    return TruncatedFlat(l, r)
end

function truncated(::Flat, l::Real, ::Nothing)
    return LeftTruncatedFlat(l)
end

function truncated(::Flat, ::Nothing, r::Real)
    return RightTruncatedFlat(r)
end


"""
    dexp(λ)

Return an Exponential distribution object with rate `λ`.

The mathematical form of the PDF for an Exponential distribution in WinBUGS is given by:

\[
f(x|λ) = λ e^{-λ x}
\]
"""
function dexp(λ)
    return Exponential(1 / λ)
end

"""
    dgamma(a, b)

Return a Gamma distribution object with shape `a` and rate `b`.

The mathematical form of the PDF for a Gamma distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{b^a}{Γ(a)} x^{a-1} e^{-bx}
\]
"""
function dgamma(a, b)
    return Gamma(a, 1 / b)
end

"""
    dchisqr(k)

Return a Chi-squared distribution object with `k` degrees of freedom.

The mathematical form of the PDF for a Chi-squared distribution in WinBUGS is given by:

\[
f(x|k) = \frac{1}{2^{k/2} Γ(k/2)} x^{k/2 - 1} e^{-x/2}
\]
"""
function dchisqr(k)
    return Chisq(k)
end

"""
    dweib(a, b)

Return a Weibull distribution object with shape `a` and scale `λ = 1 / b`.

The mathematical form of the PDF for a Weibull distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{b a (bx)^{a-1}}{e^{(bx)^a}}
\]
"""
function dweib(a, b)
    return Weibull(a, 1 / b)
end

"""
    dlnorm(μ, τ)

Return a LogNormal distribution object with location `μ` and scale `σ = 1 / √τ`.

The mathematical form of the PDF for a LogNormal distribution in WinBUGS is given by:

\[
f(x|μ,τ) = \frac{√τ}{x√{2π}} e^{-τ/2 (log(x) - μ)^2}
\]
"""
function dlnorm(μ, τ)
    return LogNormal(μ, 1 / √τ)
end

"""
    dgamma(a, b)

Return a Gamma distribution object with shape `a` and rate `b`.

The mathematical form of the PDF for a Gamma distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{b^a}{Γ(a)} x^{a-1} e^{-bx}
\]
"""
function dgamma(a, b)
    θ = 1 / b
    return Gamma(a, θ)
end

"""
    dpar(a, b)

Return a Pareto distribution object with scale `a` and shape `b`.

The mathematical form of the PDF for a Pareto distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{ba^b}{x^{b+1}}
\]
"""
function dpar(a, b)
    return Pareto(a, b)
end

"""
    dgev(μ, σ, η)

Return a GeneralizedExtremeValue distribution object with location `μ`, scale `σ`, and shape `η`.

The mathematical form of the PDF for a Generalized Extreme Value distribution in WinBUGS is given by:

\[
f(x|μ,σ,η) = \frac{1}{σ} (1 + η ((x - μ)/σ))^{-1/η - 1} e^{-(1 + η ((x - μ)/σ))^{-1/η}}
\]
"""
function dgev(μ, σ, η)
    return GeneralizedExtremeValue(μ, σ, η)
end

"""
    dgpar(μ, σ, η)

Return a GeneralizedPareto distribution object with location `μ`, scale `σ`, and shape `η`.

The mathematical form of the PDF for a Generalized Pareto distribution in WinBUGS is given by:

\[
f(x|μ,σ,η) = \frac{1}{σ} (1 + η ((x - μ)/σ))^{-1/η - 1}
\]
"""
function dgpar(μ, σ, η)
    return GeneralizedPareto(μ, σ, η)
end

"""
    df(n::Real, m::Real, μ::Real=0, τ::Real=1)

Return an F-distribution object with `n` and `m` degrees of freedom, location `μ`, and scale `τ`.
Raises a warning if `μ ≠ 0` or `τ ≠ 1`, as these cases are not fully supported.
"""
function df(n::Real, m::Real, μ::Real=0, τ::Real=1)
    if μ ≠ 0 || τ ≠ 1
        throw(ArgumentError("Non-standard location and scale parameters are not fully supported. The function will return a standard F-distribution."))
    end
    return FDist(n, m)
end

"""
    dunif(a, b)

Return a Uniform distribution object with lower bound `a` and upper bound `b`.

The mathematical form of the PDF for a Uniform distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{1}{b - a}
\]
"""
function dunif(a, b)
    return Uniform(a, b)
end

"""
    dbeta(a, b)

Return a Beta distribution object with shape parameters `a` and `b`.

The mathematical form of the PDF for a Beta distribution in WinBUGS is given by:

\[
f(x|a,b) = \frac{x^{a-1} (1 - x)^{b-1}}{B(a, b)}
\]
"""
function dbeta(a, b)
    return Beta(a, b)
end

"""
    dmnorm(μ::Vector, T::Matrix)

Return a Multivariate Normal distribution object with mean vector `μ` and precision matrix `T`.

The mathematical form of the PDF for a Multivariate Normal distribution in WinBUGS is given by:

\[
f(x|μ,T) = (2π)^{-k/2} |T|^{1/2} e^{-1/2 (x-μ)' T (x-μ)}
\]
"""
function dmnorm(μ::Vector, T::Matrix)
    return MvNormal(μ, T)
end

"""
    dmt(μ::Vector, T::Matrix, k)

Return a Multivariate T distribution object with mean vector `μ`, precision matrix `T`, and `k` degrees of freedom.

The mathematical form of the PDF for a Multivariate T distribution in WinBUGS is given by:

\[
f(x|μ,T,k) = Γ((k+p)/2) / (Γ(k/2) (kπ)^{p/2} |T|^{1/2}) (1 + 1/k (x-μ)' T (x-μ))^{-((k+p)/2)}
\]
"""
function dmt(μ::Vector, T::Matrix, k)
    return MvTDist(k, μ, T)
end

"""
    dwish(R::Matrix, k)

Return a Wishart distribution object with `k` degrees of freedom and scale matrix `R^(-1)`.

The mathematical form of the PDF for a Wishart distribution in WinBUGS is given by:

\[
f(X|R,k) = |X|^{(k-p-1)/2} e^{-1/2 tr(RX)} / (2^{kp/2} |R|^{k/2} Γ_p(k/2))
\]
"""
function dwish(R::Matrix, k)
    return Wishart(k, inv(R))
end

"""
    ddirich(θ::Vector)

Return a Dirichlet distribution object with parameters `θ`.

The mathematical form of the PDF for a Dirichlet distribution in WinBUGS is given by:

\[
f(x|θ) = Γ(∑θ) / ∏Γ(θ) ∏x^{θ-1}
\]
"""
function ddirich(θ::Vector)
    return Dirichlet(θ)
end

"""
    dbern(p)

Return a Bernoulli distribution object with success probability `p`.

The mathematical form of the PMF for a Bernoulli distribution in WinBUGS is given by:

\[
P(x|p) = p^x (1 - p)^{1-x}
\]
"""
dbern(p) = Bernoulli(p)

"""
    dbin(p, n)

Return a Binomial distribution object with number of trials `n` and success probability `p`.

The mathematical form of the PMF for a Binomial distribution in WinBUGS is given by:

\[
P(x|n,p) = C(n, x) p^x (1 - p)^{n-x}
\]
"""
dbin(p, n) = Binomial(n, p)

"""
    dcat(p)

Return a Categorical distribution object with probabilities `p`.

The mathematical form of the PMF for a Categorical distribution in WinBUGS is given by:

\[
P(x|p) = p[x]
\]
"""
dcat(p) = Categorical(p)

"""
    dpois(θ)

Return a Poisson distribution object with mean (and variance) `θ`.

The mathematical form of the PMF for a Poisson distribution in WinBUGS is given by:

\[
P(x|θ) = e^{-θ} θ^x / x!
\]
"""
dpois(θ) = Poisson(θ)

"""
    dgeom(θ)

Return a Geometric distribution object with success probability `θ`.

The mathematical form of the PMF for a Geometric distribution in WinBUGS is given by:

\[
P(x|θ) = (1 - θ)^{x-1} θ
\]
"""
dgeom(θ) = Geometric(θ)

"""
    dnegbin(p, r)

Return a Negative Binomial distribution object with number of failures `r` and success probability `p`.

The mathematical form of the PMF for a Negative Binomial distribution in WinBUGS is given by:

\[
P(x|r,p) = C(x + r - 1, x) (1 - p)^x p^r
\]
"""
dnegbin(p, r) = NegativeBinomial(r, p)

"""
    dbetabin(a, b, n)

Return a Beta Binomial distribution object with number of trials `n` and shape parameters `a` and `b`.

The mathematical form of the PMF for a Beta Binomial distribution in WinBUGS is given by:

\[
P(x|a,b,n) = C(n, x) B(x + a, n - x + b) / B(a, b)
\]
"""
dbetabin(a, b, n) = BetaBinomial(n, a, b)

"""
    dhyper(n1, n2, m1, ψ)

Return a Hypergeometric distribution object with total number of successes `n1`, total number of failures `n2`, and number of trials `m1`.

Only `ψ = 1` is currently supported for hypergeometric distribution in this function.

The mathematical form of the PMF for a Hypergeometric distribution in WinBUGS is given by:

\[
P(x|n1,n2,m1,ψ) = C(n1, x) C(n2, m1 - x) / C(n1 + n2, m1)
\]
"""
function dhyper(n1, n2, m1, ψ)
    if ψ != 1
        throw(ArgumentError("dhyper only supports ψ = 1"))
    end
    return Hypergeometric(n1, n2, m1)
end

"""
    dmulti(θ::Vector, n)

Return a Multinomial distribution object with number of trials `n` and success probabilities `θ`.

The mathematical form of the PMF for a Multinomial distribution in WinBUGS is given by:

\[
P(x|n,θ) = C(n, x) ∏θ^{x}
\]
"""
function dmulti(θ::Vector, n)
    return Multinomial(n, θ)
end
