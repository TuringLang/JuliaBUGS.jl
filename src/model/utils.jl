# TODO: can't remove even with the `possible` fix in DynamicPPL, still seems to have eltype inference issue causing AD errors
# Resolves: setindex!!([1 2; 3 4], [2 3; 4 5], 1:2, 1:2) # returns 2×2 Matrix{Any}
# Alternatively, can overload BangBang.possible(
#     ::typeof(BangBang._setindex!), ::C, ::T, ::Vararg
# )
# to allow mutation, but the current solution seems create less possible problems, albeit less efficient.
function BangBang.NoBang._setindex(xs::AbstractArray, v::AbstractArray, I...)
    T = promote_type(eltype(xs), eltype(v))
    ys = similar(xs, T)
    if eltype(xs) !== Union{}
        copy!(ys, xs)
    end
    ys[I...] = v
    return ys
end

function BangBang.setindex!!(nt::NamedTuple, val, vn::VarName{sym}) where {sym}
    optic = BangBang.prefermutation(
        AbstractPPL.getoptic(vn) ∘ Accessors.PropertyLens{sym}()
    )
    return Accessors.set(nt, optic, val)
end

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
