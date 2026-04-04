# CGGibbs: Compute Graph Gibbs sampler for GLMs
# Core types and math — no SliceSampling dependency.
# The sampling loop lives in ext/JuliaBUGSSliceSamplingExt.jl.
#
# Implements Algorithm 1 from "Is Gibbs sampling faster than HMC on GLMs?"
# (Surjanovic, Biron-Lattes, Bouchard-Côté, Luu — arXiv:2410.03630)

using LogExpFunctions: log1pexp
using SpecialFunctions: loggamma

# ======================== Link Functions ========================

abstract type AbstractLink end

struct IdentityLink <: AbstractLink end
struct LogitLink <: AbstractLink end
struct LogLink <: AbstractLink end

inv_link(::IdentityLink, η) = η
inv_link(::LogitLink, η) = one(η) / (one(η) + exp(-η))
inv_link(::LogLink, η) = exp(η)

export IdentityLink, LogitLink, LogLink

# ======================== GLM Families ==========================

abstract type AbstractFamily end

"""Gaussian family with known noise standard deviation σ (identity link)."""
struct GaussianFamily{T<:Real} <: AbstractFamily
    σ::T
end

"""Bernoulli family (logit link)."""
struct BernoulliFamily <: AbstractFamily end

"""Poisson family (log link)."""
struct PoissonFamily <: AbstractFamily end

export GaussianFamily, BernoulliFamily, PoissonFamily

# Log-likelihood of a single observation given linear predictor η.
# These operate on η directly for numerical stability.

function cg_log_lik(::BernoulliFamily, y, η)
    # y * log(σ(η)) + (1-y) * log(1-σ(η)) = y*η - log(1+exp(η))
    return y * η - log1pexp(η)
end

function cg_log_lik(f::GaussianFamily, y, η)
    residual = y - η
    return -residual^2 / (2 * f.σ^2)
end

function cg_log_lik(::PoissonFamily, y, η)
    return y * η - exp(η) - loggamma(y + 1)
end

# ======================== GLM Specification =====================

"""
    GLMSpec(X, y, link, family, priors)

Specification of a Generalized Linear Model for CGGibbs sampling.

# Fields
- `X::Matrix`: n × d design matrix
- `y::Vector`: n response vector
- `link`: Link function (IdentityLink, LogitLink, LogLink)
- `family`: Likelihood family (GaussianFamily, BernoulliFamily, PoissonFamily)
- `priors::Vector`: Prior distribution for each of the d coefficients
"""
struct GLMSpec{T<:Real,L<:AbstractLink,F<:AbstractFamily,D}
    X::Matrix{T}
    y::Vector{T}
    link::L
    family::F
    priors::Vector{D}
end

function GLMSpec(X::Matrix{T}, y::AbstractVector, link, family, priors) where {T}
    n, d = size(X)
    @assert length(y) == n "Response length ($(length(y))) must match rows of X ($n)"
    @assert length(priors) == d "Number of priors ($(length(priors))) must match columns of X ($d)"
    return GLMSpec(X, convert(Vector{T}, y), link, family, priors)
end

export GLMSpec

# ======================== Coordinate Target =====================
#
# The 1D conditional target for θ_j, using the linear predictor cache
# so that each evaluation is O(n) instead of O(dn).
#
# IMPORTANT: `cache` is NOT modified during slice sampling.

struct CoordinateTarget{T<:Real,V<:AbstractVector{T},L<:AbstractLink,F<:AbstractFamily,D}
    cache::Vector{T}
    X_col_j::V
    y::Vector{T}
    θ_j_old::T
    link::L
    family::F
    prior::D
end

function LogDensityProblems.logdensity(target::CoordinateTarget, θ_j_new)
    δ = θ_j_new - target.θ_j_old
    lp = Distributions.logpdf(target.prior, θ_j_new)

    @inbounds for i in eachindex(target.y)
        η_i = target.cache[i] + δ * target.X_col_j[i]
        lp += cg_log_lik(target.family, target.y[i], η_i)
    end

    return lp
end

LogDensityProblems.capabilities(::Type{<:CoordinateTarget}) = LogDensityProblems.LogDensityOrder{
    0
}()
LogDensityProblems.dimension(::CoordinateTarget) = 1

# ======================== CGGibbs Sampler =======================

"""
    CGGibbsSampler(glm; slice, random_scan)

Compute Graph Gibbs sampler for GLMs. Requires `SliceSampling.jl` to be loaded.

# Arguments
- `glm::GLMSpec`: GLM specification
- `slice`: Univariate slice sampling algorithm (default: `SliceDoublingOut(2.0)`)
- `random_scan::Bool`: Random permutation scan (default: true)

# Usage
```julia
using SliceSampling  # required for cg_gibbs_sample

glm = GLMSpec(X, y, LogitLink(), BernoulliFamily(), priors)
sampler = CGGibbsSampler(glm)
samples, logps = cg_gibbs_sample(rng, sampler; n_samples=1000, n_warmup=500)
```
"""
struct CGGibbsSampler{S}
    glm::GLMSpec
    slice::S
    random_scan::Bool
end

export CGGibbsSampler

# Compute full log-density for diagnostics (not used in inner loop)
function cg_full_logdensity(glm::GLMSpec, θ::AbstractVector, cache::AbstractVector)
    lp = zero(eltype(θ))
    @inbounds for j in eachindex(θ)
        lp += Distributions.logpdf(glm.priors[j], θ[j])
    end
    @inbounds for i in eachindex(glm.y)
        lp += cg_log_lik(glm.family, glm.y[i], cache[i])
    end
    return lp
end

"""
    cg_gibbs_sample(rng, sampler; n_samples, n_warmup, initial_θ)

Run the CGGibbs sampler. Requires `SliceSampling.jl` to be loaded.
Defined in the JuliaBUGSSliceSamplingExt extension.
"""
function cg_gibbs_sample end

export cg_gibbs_sample

# ======================== Horseshoe Prior ======================
#
# Multi-block Gibbs sampler for the horseshoe prior
# (Carvalho, Polson & Scott 2010; Surjanovic et al. 2024, Section A.2).

# ---- LambdaTarget: full conditional for local shrinkage λ_j ----
# log p(λ_j | θ_j, τ) = -log(1 + λ_j²) - log(λ_j) - θ_j² / (2λ_j²τ²)

struct LambdaTarget{T<:Real}
    theta_j::T
    tau::T
end

function LogDensityProblems.logdensity(t::LambdaTarget, lambda_j)
    lambda_j <= 0 && return -Inf
    ratio = t.theta_j / (lambda_j * t.tau)
    return -log(1 + lambda_j^2) - log(lambda_j) - ratio^2 / 2
end

LogDensityProblems.capabilities(::Type{<:LambdaTarget}) = LogDensityProblems.LogDensityOrder{
    0
}()
LogDensityProblems.dimension(::LambdaTarget) = 1

# ---- TauTarget: full conditional for global shrinkage τ ----
# log p(τ | θ_{2:d}, λ) = -log(1 + τ²) - (d-1)log(τ) - (1/2τ²) Σ (θ_j/λ_j)²

struct TauTarget{T<:Real}
    sum_sq::T       # precomputed: Σ (θ_j / λ_j)²
    d_minus_1::Int
end

function TauTarget(theta_rest::AbstractVector{T}, lambda::AbstractVector{T}) where {T}
    sum_sq = zero(T)
    @inbounds for j in eachindex(theta_rest)
        ratio = theta_rest[j] / lambda[j]
        sum_sq += ratio * ratio
    end
    return TauTarget{T}(sum_sq, length(theta_rest))
end

function LogDensityProblems.logdensity(t::TauTarget, tau)
    tau <= 0 && return -Inf
    return -log(1 + tau^2) - t.d_minus_1 * log(tau) - t.sum_sq / (2 * tau^2)
end

LogDensityProblems.capabilities(::Type{<:TauTarget}) = LogDensityProblems.LogDensityOrder{
    0
}()
LogDensityProblems.dimension(::TauTarget) = 1

# ---- HorseshoeModel ----

"""
    HorseshoeModel(X, y, link, family)

GLM with horseshoe prior for CGGibbs sampling.

Prior structure:
- θ₁ ~ t(3, 0, 1)  (intercept)
- θⱼ ~ Normal(0, λⱼ² τ²)  for j = 2, …, d
- λⱼ ~ HalfCauchy(0, 1)
- τ  ~ HalfCauchy(0, 1)
"""
struct HorseshoeModel{T<:Real,L<:AbstractLink,F<:AbstractFamily}
    X::Matrix{T}
    y::Vector{T}
    link::L
    family::F

    function HorseshoeModel(
        X::Matrix{T}, y::AbstractVector, link::L, family::F
    ) where {T<:Real,L<:AbstractLink,F<:AbstractFamily}
        n, d = size(X)
        @assert length(y) == n "Response length ($(length(y))) must match rows of X ($n)"
        @assert d >= 2 "Design matrix must have at least 2 columns (intercept + 1 predictor)"
        return new{T,L,F}(X, convert(Vector{T}, y), link, family)
    end
end

export HorseshoeModel

"""
    horseshoe_sample(rng, model; n_samples, n_warmup, ...)

Multi-block Gibbs sampler for GLMs with horseshoe prior. Requires `SliceSampling.jl`.
Defined in the JuliaBUGSSliceSamplingExt extension.
"""
function horseshoe_sample end

export horseshoe_sample
