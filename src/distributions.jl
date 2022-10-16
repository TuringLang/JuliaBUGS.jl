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