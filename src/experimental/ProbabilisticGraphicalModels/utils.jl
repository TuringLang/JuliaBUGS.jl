"""
    reconstruct([f, ]dist, val)

Reconstruct `val` so that it's compatible with `dist`.

If `f` is also provided, the reconstruct value will be
such that `f(reconstruct_val)` is compatible with `dist`.
"""
reconstruct(f, dist, val) = reconstruct(dist, val)

# No-op versions.
reconstruct(::UnivariateDistribution, val::Real) = val
reconstruct(::MultivariateDistribution, val::AbstractVector{<:Real}) = copy(val)
reconstruct(::MatrixDistribution, val::AbstractMatrix{<:Real}) = copy(val)
function reconstruct(
    ::Distribution{ArrayLikeVariate{N}}, val::AbstractArray{<:Real,N}
) where {N}
    return copy(val)
end

function reconstruct(dist::LKJCholesky, val::AbstractVector{<:Real})
    return reconstruct(dist, Matrix(reshape(val, size(dist))))
end
reconstruct(dist::LKJCholesky, val::AbstractMatrix{<:Real}) = Cholesky(val, dist.uplo, 0)
reconstruct(::LKJCholesky, val::Cholesky) = val

# NOTE: Necessary to handle product distributions of `Dirichlet` and similar.
function reconstruct(
    ::Bijectors.Inverse{<:Bijectors.SimplexBijector}, dist, val::AbstractVector
)
    (d, ns...) = size(dist)
    return reshape(val, d - 1, ns...)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.VecCorrBijector}, ::LKJ, val::AbstractVector
)
    return copy(val)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.VecCholeskyBijector}, ::LKJCholesky, val::AbstractVector
)
    return copy(val)
end
function reconstruct(
    ::Bijectors.Inverse{Bijectors.PDVecBijector}, ::MatrixDistribution, val::AbstractVector
)
    return copy(val)
end

reconstruct(d::Distribution, val::AbstractVector) = reconstruct(size(d), val)
reconstruct(::Tuple{}, val::AbstractVector) = val[1]
reconstruct(s::NTuple{1}, val::AbstractVector) = copy(val)
reconstruct(s::NTuple{2}, val::AbstractVector) = reshape(copy(val), s)
