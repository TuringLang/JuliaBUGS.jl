module JuliaBUGSSliceSamplingExt

using JuliaBUGS
using JuliaBUGS:
    GLMSpec,
    CGGibbsSampler,
    CoordinateTarget,
    cg_full_logdensity,
    HorseshoeModel,
    LambdaTarget,
    TauTarget,
    cg_log_lik
using JuliaBUGS.LogDensityProblems
using JuliaBUGS.Distributions: TDist, Normal
using JuliaBUGS.Random
using JuliaBUGS.LogExpFunctions: log1p
using SliceSampling: SliceSampling, SliceDoublingOut

"""
    CGGibbsSampler(glm; slice=SliceDoublingOut(2.0), random_scan=true)

Construct a CGGibbs sampler with default slice sampling parameters.
"""
function JuliaBUGS.CGGibbsSampler(
    glm::GLMSpec; slice=SliceDoublingOut(2.0), random_scan=true
)
    return CGGibbsSampler(glm, slice, random_scan)
end

"""
    cg_gibbs_sample(rng, sampler; n_samples=1000, n_warmup=500, initial_θ=nothing)

Run the CGGibbs sampler and return:
- `samples`: `n_samples × d` matrix of posterior samples
- `logps`:   `n_samples` vector of log-densities

Uses linear predictor caching for O(dn) per sweep instead of O(d²n).
"""
function JuliaBUGS.cg_gibbs_sample(
    rng::Random.AbstractRNG,
    sampler::CGGibbsSampler;
    n_samples::Int=1000,
    n_warmup::Int=500,
    initial_θ::Union{Nothing,Vector}=nothing,
)
    glm = sampler.glm
    X, y = glm.X, glm.y
    n, d = size(X)

    # Initialize parameter vector and cache
    θ = if isnothing(initial_θ)
        zeros(eltype(X), d)
    else
        copy(convert(Vector{eltype(X)}, initial_θ))
    end
    cache = X * θ   # n-vector: cache[i] = x_i^T θ

    # Pre-allocate output
    samples = Matrix{eltype(X)}(undef, n_samples, d)
    logps = Vector{eltype(X)}(undef, n_samples)

    total_iters = n_samples + n_warmup

    for iter in 1:total_iters
        # Determine coordinate scan order
        perm = sampler.random_scan ? randperm(rng, d) : collect(1:d)

        for j in perm
            X_col_j = @view X[:, j]

            # Build 1D conditional target using cache
            target = CoordinateTarget(
                cache, X_col_j, y, θ[j], glm.link, glm.family, glm.priors[j]
            )

            # Current log-density at θ[j]
            ℓπ_current = LogDensityProblems.logdensity(target, θ[j])

            # Slice sample the new value of θ[j]
            θ_j_new, _, _ = SliceSampling.slice_sampling_univariate(
                rng, sampler.slice, target, ℓπ_current, θ[j]
            )

            # Update cache: cache[i] += (θ_j_new - θ_j_old) * X[i,j]
            δ = θ_j_new - θ[j]
            if δ != 0
                @inbounds for i in 1:n
                    cache[i] += δ * X_col_j[i]
                end
            end

            θ[j] = θ_j_new
        end

        # Store post-warmup samples
        if iter > n_warmup
            s = iter - n_warmup
            @inbounds samples[s, :] .= θ
            logps[s] = cg_full_logdensity(glm, θ, cache)
        end
    end

    return samples, logps
end

# Convenience method with default RNG
function JuliaBUGS.cg_gibbs_sample(sampler::CGGibbsSampler; kwargs...)
    return JuliaBUGS.cg_gibbs_sample(Random.default_rng(), sampler; kwargs...)
end

# ======================== Horseshoe Sampling ====================

"""
    horseshoe_sample(rng, model; n_samples, n_warmup, ...) -> (theta, lambda, tau, logps)

Multi-block Gibbs sampler for GLMs with horseshoe prior.

Three blocks per iteration:
1. Update θ via CGGibbs sweep (priors rebuilt from current λ, τ)
2. Update each λ_j via slice sampling from full conditional
3. Update τ via slice sampling from full conditional
"""
function JuliaBUGS.horseshoe_sample(
    rng::Random.AbstractRNG,
    model::HorseshoeModel{T};
    n_samples::Int=1000,
    n_warmup::Int=500,
    slice_theta=SliceDoublingOut(2.0),
    slice_hyper=SliceDoublingOut(1.0),
    random_scan::Bool=true,
    initial_theta::Union{Nothing,Vector}=nothing,
    initial_lambda::Union{Nothing,Vector}=nothing,
    initial_tau::Union{Nothing,Real}=nothing,
) where {T}
    X, y = model.X, model.y
    n, d = size(X)

    # Initialize parameters
    θ = isnothing(initial_theta) ? zeros(T, d) : copy(convert(Vector{T}, initial_theta))
    lambda = if isnothing(initial_lambda)
        ones(T, d - 1)
    else
        copy(convert(Vector{T}, initial_lambda))
    end
    tau = isnothing(initial_tau) ? one(T) : T(initial_tau)

    # Linear predictor cache
    cache = X * θ

    # Pre-allocate output
    theta_samples = Matrix{T}(undef, n_samples, d)
    lambda_samples = Matrix{T}(undef, n_samples, d - 1)
    tau_samples = Vector{T}(undef, n_samples)
    logps = Vector{T}(undef, n_samples)

    total_iters = n_samples + n_warmup

    for iter in 1:total_iters
        # ---- Block 1: Update θ via CGGibbs sweep ----
        priors = Vector{JuliaBUGS.Distributions.ContinuousUnivariateDistribution}(undef, d)
        priors[1] = TDist(3)
        @inbounds for j in 2:d
            priors[j] = Normal(0, lambda[j - 1] * tau)
        end

        perm = random_scan ? randperm(rng, d) : collect(1:d)

        for j in perm
            X_col_j = @view X[:, j]
            target = CoordinateTarget(
                cache, X_col_j, y, θ[j], model.link, model.family, priors[j]
            )
            ℓπ_current = LogDensityProblems.logdensity(target, θ[j])
            θ_j_new, _, _ = SliceSampling.slice_sampling_univariate(
                rng, slice_theta, target, ℓπ_current, θ[j]
            )
            δ = θ_j_new - θ[j]
            if δ != 0
                @inbounds for i in 1:n
                    cache[i] += δ * X_col_j[i]
                end
            end
            θ[j] = θ_j_new
        end

        # ---- Block 2: Update each λ_j via slice sampling ----
        @inbounds for j in 1:(d - 1)
            lt = LambdaTarget(θ[j + 1], tau)
            ℓπ_current = LogDensityProblems.logdensity(lt, lambda[j])
            lambda_new, _, _ = SliceSampling.slice_sampling_univariate(
                rng, slice_hyper, lt, ℓπ_current, lambda[j]
            )
            lambda[j] = lambda_new
        end

        # ---- Block 3: Update τ via slice sampling ----
        theta_rest = @view θ[2:d]
        tt = TauTarget(theta_rest, lambda)
        ℓπ_current = LogDensityProblems.logdensity(tt, tau)
        tau_new, _, _ = SliceSampling.slice_sampling_univariate(
            rng, slice_hyper, tt, ℓπ_current, tau
        )
        tau = tau_new

        # Store post-warmup samples
        if iter > n_warmup
            s = iter - n_warmup
            @inbounds theta_samples[s, :] .= θ
            @inbounds lambda_samples[s, :] .= lambda
            tau_samples[s] = tau
            logps[s] = _horseshoe_logdensity(model, θ, lambda, tau, cache)
        end
    end

    return theta_samples, lambda_samples, tau_samples, logps
end

# Convenience: default RNG
function JuliaBUGS.horseshoe_sample(model::HorseshoeModel; kwargs...)
    return JuliaBUGS.horseshoe_sample(Random.default_rng(), model; kwargs...)
end

"""Full log-density for horseshoe model (likelihood + prior), for diagnostics."""
function _horseshoe_logdensity(model::HorseshoeModel{T}, θ, lambda, tau, cache) where {T}
    lp = zero(T)

    # Intercept prior: t(3)
    lp += JuliaBUGS.Distributions.logpdf(TDist(3), θ[1])

    # Coefficient priors + half-Cauchy priors on λ
    d = length(θ)
    @inbounds for j in 2:d
        lp += JuliaBUGS.Distributions.logpdf(Normal(0, lambda[j - 1] * tau), θ[j])
        lp += -log1p(lambda[j - 1]^2) - log(T(π) / 2)
    end

    # τ ~ HalfCauchy(0,1)
    lp += -log1p(tau^2) - log(T(π) / 2)

    # Likelihood
    @inbounds for i in eachindex(model.y)
        lp += cg_log_lik(model.family, model.y[i], cache[i])
    end

    return lp
end

end
