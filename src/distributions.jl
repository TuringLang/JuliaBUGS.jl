# Support for distributions that are part of BUGS but not implemented in Distributions.jl.

# Modified from https://github.com/TuringLang/Turing.jl/blob/master/src/stdlib/distributions.jl
# Rename `Flat` to `SPPLFlat` to avoid name conflict with Turing.jl
"""
    Flat

The *flat distribution* is the improper distribution of real numbers that has the improper
probability density function
```math
f(x) = 1.
```
"""
struct SPPLFlat <: ContinuousUnivariateDistribution end

Base.minimum(::SPPLFlat) = -Inf
Base.maximum(::SPPLFlat) = Inf

Base.rand(rng::Random.AbstractRNG, d::SPPLFlat) = rand(rng)
Distributions.logpdf(::SPPLFlat, x::Real) = zero(x)

# TODO: only implement `logpdf(d, ::Real)` if support for Distributions < 0.24 is dropped
Distributions.pdf(d::SPPLFlat, x::Real) = exp(logpdf(d, x))
Distributions.cdf(d::SPPLFlat, x::Real) = 0

# For vec support
Distributions.logpdf(::SPPLFlat, x::AbstractVector{<:Real}) = zero(x)
Distributions.loglikelihood(::SPPLFlat, x::AbstractVector{<:Real}) = zero(eltype(x))

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

# TODO: only implement `logpdf(d, ::Real)` if support for Distributions < 0.24 is dropped
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

# TODO: only implement `logpdf(d, ::Real)` if support for Distributions < 0.24 is dropped
Distributions.pdf(d::RightTruncatedFlat, x::Real) = exp(logpdf(d, x))
Distributions.cdf(d::RightTruncatedFlat, x::Real) = 0

# For vec support
function Distributions.loglikelihood(d::RightTruncatedFlat, x::AbstractVector{<:Real})
    upper = d.r
    T = float(eltype(x))
    return any(xi >= upper for xi in x) ? T(Inf) : zero(T)
end

function truncated(d::SPPLFlat, l::Real, r::Real)
    if l > r
        throw(ArgumentError("invalid truncation interval: $l > $r"))
    end
    return Uniform(l, r)
end

function truncated(d::SPPLFlat, l::Real, ::Nothing)
    return LeftTruncatedFlat(l)
end

function truncated(d::SPPLFlat, ::Nothing, r::Real)
    return RightTruncatedFlat(r)
end