"""
    dnorm(μ, τ)

Returns an instance of [Normal](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Normal) 
with mean ``μ`` and standard deviation ``\\frac{1}{√τ}``. 

```math
p(x|μ,τ) = \\sqrt{\\frac{τ}{2π}} e^{-τ \\frac{(x-μ)^2}{2}}
```
"""
function dnorm(μ, τ)
    if τ < 0
        throw(DomainError((μ, τ), "Requires τ > 0"))
    end
    σ² = 1 / τ # variance
    σ = √σ² # standard deviation
    return Normal(μ, σ)
end

"""
    dlogis(μ, τ)

Return an instance of [Logistic](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Logistic) 
with location parameter ``μ`` and scale parameter ``\\frac{1}{√τ}``.

```math
p(x|μ,τ) = \\frac{\\sqrt{τ} e^{-\\sqrt{τ}(x-μ)}}{(1+e^{-\\sqrt{τ}(x-μ)})^2}
```
"""
function dlogis(μ, τ)
    s = 1 / √τ
    return Logistic(μ, s)
end

"""
    TDistShiftedScaled(ν, μ, σ)

Student's t-distribution with ``ν`` degrees of freedom, location ``μ``, and scale ``σ``. 

This struct allows for a shift (determined by ``μ``) and a scale (determined by ``σ``) of the standard 
Student's t-distribution provided by the [Distributions.jl](https://github.com/JuliaStats/Distributions.jl) 
package. 

Only `pdf` and `logpdf` are implemented for this distribution.

# See Also
[TDist](https://juliastats.org/Distributions.jl/stable/univariate/#Distributions.TDist)
"""
struct TDistShiftedScaled <: Distributions.ContinuousUnivariateDistribution
    ν::Real
    μ::Real
    σ::Real

    TDistShiftedScaled(ν::Real, μ::Real, σ::Real) = new(ν, μ, σ)
end

Distributions.pdf(d::TDistShiftedScaled, x::Real) = pdf(TDist(d.ν), (x - d.μ) / d.σ) / d.σ
function Distributions.logpdf(d::TDistShiftedScaled, x::Real)
    return logpdf(TDist(d.ν), (x - d.μ) / d.σ) - log(d.σ)
end

"""
    dt(μ, τ, ν)

If ``μ = 0`` and ``σ = 1``, the function returns an instance of [TDist](https://juliastats.org/Distributions.jl/stable/univariate/#Distributions.TDist) 
with ``ν`` degrees of freedom, location ``μ``, and scale ``σ = \\frac{1}{\\sqrt{τ}}``. Otherwise, it returns an instance of [`TDistShiftedScaled`](@ref).

```math
p(x|ν,μ,σ) = \\frac{Γ((ν+1)/2)}{Γ(ν/2) \\sqrt{νπσ}}
\\left(1+\\frac{1}{ν}\\left(\\frac{x-μ}{σ}\\right)^2\\right)^{-\\frac{ν+1}{2}}
```
"""
function dt(μ, τ, ν)
    σ = sqrt(1 / τ)
    if μ == 0 && σ == 1
        return TDist(ν)
    else
        return TDistShiftedScaled(ν, μ, σ)
    end
end

"""
    ddexp(μ, τ)

Return an instance of [Laplace (Double Exponential)](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Laplace) 
with location ``μ`` and scale ``\\frac{1}{\\sqrt{τ}}``.

```math
p(x|μ,τ) = \\frac{\\sqrt{τ}}{2} e^{-\\sqrt{τ} |x-μ|}
```
"""
function ddexp(μ, τ)
    b = 1 / √τ
    return Laplace(μ, b)
end

"""
    dflat()

Returns an instance of [`Flat`](@ref) or [`TruncatedFlat`](@ref) if truncated.

`Flat` represents a flat (uniform) prior over the real line, which is an improper distribution. And 
`TruncatedFlat` represents a truncated version of the `Flat` distribution.

Only `pdf`, `logpdf`, `minimum`, and `maximum` are implemented for these Distributions.

When use in a model, the parameters always need to be initialized.
"""
dflat() = Flat()

"""
    Flat

The flat distribution mimicking the behavior of the `dflat` distribution in the BUGS family of softwares.
"""
struct Flat <: Distributions.ContinuousUnivariateDistribution end

Distributions.minimum(::Flat) = -Inf
Distributions.maximum(::Flat) = Inf

Distributions.pdf(::Flat, x::Real) = 1.0
Distributions.logpdf(::Flat, x::Real) = 0.0

struct LeftTruncatedFlat <: Distributions.ContinuousUnivariateDistribution
    a::Real
end

Distributions.minimum(d::LeftTruncatedFlat) = d.a
Distributions.maximum(::LeftTruncatedFlat) = Inf

Distributions.pdf(d::LeftTruncatedFlat, x::Real) = x >= d.a ? 1.0 : 0.0
Distributions.logpdf(d::LeftTruncatedFlat, x::Real) = x >= d.a ? 0.0 : -Inf

struct RightTruncatedFlat <: Distributions.ContinuousUnivariateDistribution
    b::Real
end

Distributions.minimum(::RightTruncatedFlat) = -Inf
Distributions.maximum(d::RightTruncatedFlat) = d.b

Distributions.pdf(d::RightTruncatedFlat, x::Real) = x <= d.b ? 1.0 : 0.0
Distributions.logpdf(d::RightTruncatedFlat, x::Real) = x <= d.b ? 0.0 : -Inf

"""
    TruncatedFlat

Truncated version of the [`Flat`](@ref) distribution.
"""
struct TruncatedFlat <: Distributions.ContinuousUnivariateDistribution
    a::Real
    b::Real

    function TruncatedFlat(a::Real, b::Real)
        return (a < b) ? new(a, b) : throw(DomainError((a, b), "Requires a < b"))
    end
end

Distributions.minimum(d::TruncatedFlat) = d.a
Distributions.maximum(d::TruncatedFlat) = d.b

Distributions.pdf(d::TruncatedFlat, x::Real) = (d.a <= x <= d.b) ? 1.0 / (d.b - d.a) : 0.0
Distributions.logpdf(d::TruncatedFlat, x::Real) = log(pdf(d, x))

function Distributions.truncated(::Flat, l::Real, r::Real)
    return TruncatedFlat(l, r)
end

function Distributions.truncated(::Flat, l::Real, ::Nothing)
    return LeftTruncatedFlat(l)
end

function Distributions.truncated(::Flat, ::Nothing, r::Real)
    return RightTruncatedFlat(r)
end

"""
    dexp(λ)

Returns an instance of [Exponential](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Exponential) 
with rate ``\\frac{1}{λ}``.

```math
p(x|λ) = λ e^{-λ x}
```
"""
function dexp(λ)
    return Exponential(1 / λ)
end

"""
    dgamma(a, b)

Returns an instance of [Gamma](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Gamma) 
with shape ``a`` and scale ``\\frac{1}{b}``.

```math
p(x|a,b) = \\frac{b^a}{Γ(a)} x^{a-1} e^{-bx}
```
"""
function dgamma(a, b)
    θ = 1 / b
    return Gamma(a, θ)
end

"""
    dchisqr(k)

Returns an instance of [Chi-squared](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Chisq) 
with ``k`` degrees of freedom.

```math
p(x|k) = \\frac{1}{2^{k/2} Γ(k/2)} x^{k/2 - 1} e^{-x/2}
```
"""
function dchisqr(k)
    return Chisq(k)
end

"""
    dweib(a, b)

Returns an instance of [Weibull](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Weibull) 
distribution object with shape parameter ``a`` and scale parameter ``\\frac{1}{b}``.

The Weibull distribution is a common model for event times. The hazard or instantaneous risk of the event 
is ``abx^{a-1}``. For ``a < 1`` the hazard decreases with ``x``; for ``a > 1`` it increases. 
``a = 1`` results in the exponential distribution with constant hazard.

```math
p(x|a,b) = abx^{a-1}e^{-b x^a}
```
"""
function dweib(a, b)
    return Weibull(a, 1 / b)
end

"""
    dlnorm(μ, τ)

Returns an instance of [LogNormal](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.LogNormal) 
with location ``μ`` and scale ``\\frac{1}{\\sqrt{τ}}``.

```math
p(x|μ,τ) = \\frac{\\sqrt{τ}}{x\\sqrt{2π}} e^{-τ/2 (\\log(x) - μ)^2}
```
"""
function dlnorm(μ, τ)
    return LogNormal(μ, 1 / √τ)
end

"""
    dpar(a, b)

Returns an instance of [Pareto](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Pareto) 
with scale parameter ``b`` and shape parameter ``a``.

```math
p(x|a,b) = \\frac{a b^a}{x^{a+1}}
```
"""
function dpar(a, b)
    return Pareto(b, a)
end

"""
    dgev(μ, σ, η)

Returns an instance of [GeneralizedExtremeValue](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.GeneralizedExtremeValue) 
with location ``μ``, scale ``σ``, and shape ``η``.

```math
p(x|μ,σ,η) = \\frac{1}{σ} \\left(1 + η \\frac{x - μ}{σ}\\right)^{-\\frac{1}{η} - 1} e^{-\\left(1 + η \\frac{x - μ}{σ}\\right)^{-\\frac{1}{η}}}
```

where ``\\frac{η(x - μ)}{σ} > -1``.
"""
function dgev(μ, σ, η)
    if 1 + η * (σ / μ) ≤ 0
        throw(
            DomainError(
                (μ, σ, η),
                "The expression 1 + η ((x - μ)/σ) must be greater than zero for the function to be defined.",
            ),
        )
    end
    return GeneralizedExtremeValue(μ, σ, η)
end

"""
    dgpar(μ, σ, η)

Returns an instance of [GeneralizedPareto](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.GeneralizedPareto) 
with location ``μ``, scale ``σ``, and shape ``η``.

```math
p(x|μ,σ,η) = \\frac{1}{σ} (1 + η ((x - μ)/σ))^{-1/η - 1}
```
"""
function dgpar(μ, σ, η)
    return GeneralizedPareto(μ, σ, η)
end

"""
    df(n, m, μ=0, τ=1)

Returns an instance of [F-distribution](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.FDist) 
object with ``n`` and ``m`` degrees of freedom, location ``μ``, and scale ``τ``.
This function is only valid when ``μ = 0`` and ``τ = 1``,

```math
p(x|n, m, μ, τ) = \\frac{\\Gamma\\left(\\frac{n+m}{2}\\right)}{\\Gamma\\left(\\frac{n}{2}\\right) \\Gamma\\left(\\frac{m}{2}\\right)} \\left(\\frac{n}{m}\\right)^{\\frac{n}{2}} \\sqrt{τ} \\left(\\sqrt{τ}(x - μ)\\right)^{\\frac{n}{2}-1} \\left(1 + \\frac{n \\sqrt{τ}(x-μ)}{m}\\right)^{-\\frac{n+m}{2}}
```
where ``\\frac{n \\sqrt{τ} (x - μ)}{m} > -1``.
"""
function df(n::Real, m::Real, μ::Real=0, τ::Real=1)
    if μ ≠ 0 || τ ≠ 1
        throw(
            ArgumentError(
                "Non-standard location and scale parameters are not fully supported. The function will return a standard F-distribution.",
            ),
        )
    elseif 1 + n * √τ * (μ / m) ≤ 0
        throw(
            DomainError(
                (n, m, μ, τ),
                "The expression 1 + n sqrt(τ)(x - μ) / m must be greater than zero for the function to be defined.",
            ),
        )
    end
    return FDist(n, m)
end

"""
    dunif(a, b)

Returns an instance of [Uniform](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Uniform) 
with lower bound ``a`` and upper bound ``b``.

```math
p(x|a,b) = \\frac{1}{b - a}
```
"""
function dunif(a, b)
    return Uniform(a, b)
end

"""
    dbeta(a, b)

Returns an instance of [Beta](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Beta) 
with shape parameters ``a`` and ``b``.

```math
p(x|a,b) = \\frac{\\Gamma(a + b)}{\\Gamma(a)\\Gamma(b)} x^{a-1} (1 - x)^{b-1}
```
"""
function dbeta(a, b)
    return Beta(a, b)
end

"""
    dmnorm(μ::AbstractVector, T::AbstractMatrix)

Returns an instance of [Multivariate Normal in canonical form](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.MvNormalCanon) 
with mean vector `μ` and precision matrix `T`.

```math
p(x|μ,T) = (2π)^{-k/2} |T|^{1/2} e^{-1/2 (x-μ)' T (x-μ)}
```
where ``k`` is the dimension of `x`.
"""
function dmnorm(μ::AbstractVector, T::AbstractMatrix)
    return Distributions.MvNormalCanon(μ, PDMat(T))
end

"""
    dmt(μ::AbstractVector, T::AbstractMatrix, k)

Returns an instance of [Multivariate T](https://github.com/JuliaStats/Distributions.jl/blob/master/src/multivariate/mvtdist.jl) 
with mean vector ``μ``, scale matrix ``T^{-1}``, and ``k`` degrees of freedom.

```math
p(x|k,μ,Σ) = \\frac{\\Gamma((k+d)/2)}{\\Gamma(k/2) (k\\pi)^{p/2} |Σ|^{1/2}} \\left(1 + \\frac{1}{k} (x-μ)^T Σ^{-1} (x-μ)\\right)^{-\\frac{k+p}{2}}
```
where ``p`` is the dimension of ``x``.
"""
function dmt(μ::AbstractVector, T::AbstractMatrix, k)
    return MvTDist(k, μ, _inv(PDMat(T)))
end

"""
    dwish(R::AbstractMatrix, k)

Returns an instance of [Wishart](https://juliastats.org/Distributions.jl/latest/matrix/#Distributions.Wishart) 
with ``k`` degrees of freedom and the scale matrix ``T^{-1}``.

```math
p(X|R,k) = |R|^{k/2} |X|^{(k-p-1)/2} e^{-(1/2) tr(RX)} / (2^{kp/2} Γ_p(k/2))
```
where ``p`` is the dimension of ``X``, and it should be less than or equal to ``k``. 
"""
function dwish(R::AbstractMatrix, k)
    if k < size(R, 1)
        throw(
            ArgumentError(
                "The degrees of freedom must be greater than or equal to the dimension of the scale matrix.",
            ),
        )
    end
    return Wishart(k, _inv(PDMat(R)))
end

"""
    ddirich(θ::AbstractVector)

Return an instance of [Dirichlet](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Dirichlet) 
with parameters ``θ_i``.

```math
p(x|θ) = \\frac{Γ(\\sum θ)}{∏ Γ(θ)} ∏ x_i^{θ_i - 1}
```
where ``\\theta_i > 0, x_i \\in [0, 1], \\sum_i x_i = 1``
"""
function ddirich(θ::AbstractVector)
    return Dirichlet(θ)
end

"""
    dbern(p)

Return an instance of [Bernoulli](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Bernoulli) 
with success probability `p`.

```math
p(x|p) = p^x (1 - p)^{1-x}
```
"""
function dbern(p)
    return Bernoulli(p)
end

"""
    dbin(p, n)

Returns an instance of [Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Binomial) 
with number of trials `n` and success probability `p`.

```math
p(x|n,p) = \\binom{n}{x} p^x (1 - p)^{n-x}
```end

where ``\\theta \\in [0, 1], n \\in \\mathbb{Z}^+,`` and ``x = 0, \\ldots, n``.
"""
function dbin(p, n)
    return Binomial(n, p)
end

"""
    dcat(p)

Returns an instance of [Categorical](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Categorical) 
with probabilities `p`.

```math
p(x|p) = p[x]
```
"""
function dcat(p)
    return Categorical(p)
end

"""
    dpois(θ)

Returns an instance of [Poisson](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Poisson) 
with mean (and variance) `θ`.

```math
p(x|θ) = e^{-θ} θ^x / x!
```
"""
function dpois(θ)
    return Poisson(θ)
end

"""
    dgeom(θ)

Returns an instance of [Geometric](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Geometric) 
with success probability `θ`.

```math
p(x|θ) = (1 - θ)^{x-1} θ
```
"""
function dgeom(θ)
    return Geometric(θ)
end

"""
    dnegbin(p, r)

Returns an instance of [Negative Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.NegativeBinomial) 
with number of failures `r` and success probability `p`.

```math
P(x|r,p) = \\binom{x + r - 1}{x} (1 - p)^x p^r
```

where ``x \\in \\mathbb{Z}^+``.
"""
function dnegbin(p, r)
    return NegativeBinomial(r, p)
end

"""
    dbetabin(a, b, n)

Returns an instance of [Beta Binomial](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.BetaBinomial) 
with number of trials `n` and shape parameters `a` and `b`.

```math
P(x|a, b, n) = \\frac{\\binom{n}{x} \\binom{a + b - 1}{a + x - 1}}{\\binom{a + b + n - 1}{n}}
```
"""
function dbetabin(a, b, n)
    return BetaBinomial(n, a, b)
end

"""
    dhyper(n₁, n₂, m₁, ψ=1)

Returns an instance of [Hypergeometric](https://juliastats.org/Distributions.jl/latest/univariate/#Distributions.Hypergeometric). 
This distribution is used when sampling without replacement from a population consisting of 
``n₁`` successes and ``n₂`` failures, with ``m₁`` being the number of trials or the sample size. 
The function currently only allows for ``ψ = 1``.

```math
p(x | n₁, n₂, m₁, \\psi) = \\frac{\\binom{n₁}{x} \\binom{n₂}{m₁ - x} \\psi^x}{\\sum_{i=u_0}^{u_1} \\binom{n1}{i} \\binom{n2}{m₁ - i} \\psi^i}
```
where ``u_0 = \\max(0, m₁-n₂), u_1 = \\min(n₁,m₁),`` and ``u_0 \\leq x \\leq u_1``
"""
function dhyper(n1, n2, m1, ψ)
    if ψ != 1
        throw(ArgumentError("dhyper only supports ψ = 1"))
    end
    return Hypergeometric(n1, n2, m1)
end

"""
    dmulti(θ::AbstractVector, n)

Returns an instance [Multinomial](https://juliastats.org/Distributions.jl/latest/multivariate/#Distributions.Multinomial) 
with number of trials `n` and success probabilities `θ`.

```math
P(x|n,θ) = \\frac{n!}{∏_{r} x_{r}!} ∏_{r} θ_{r}^{x_{r}}
```
"""
function dmulti(θ::AbstractVector, n)
    return Multinomial(n, θ)
end
