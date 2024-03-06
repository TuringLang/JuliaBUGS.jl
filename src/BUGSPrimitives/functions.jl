"""
    equals(x, y)

Returns 1 if ``x`` is equal to ``y``, 0 otherwise.
"""
function equals(x, y)
    return x == y ? 1 : 0
end

"""
    icloglog(x)

Inverse complementary log-log function of ``x``. Alias for [`cexpexp(x)`](@ref).
"""
function icloglog(x)
    return cexpexp(x)
end

"""
    ilogit(x)

Inverse logit function of ``x``. Alias for [`logistic(x)`](@ref).
"""
function ilogit(x)
    return logistic(x)
end

"""
    inprod(a, b)

Inner product of ``a`` and ``b``.
"""
function inprod(a, b)
    return a * b
end

"""
    inverse(m::AbstractMatrix)

Inverse of matrix ``\\mathbf{m}``.
"""
function inverse(m::AbstractMatrix)
    return LinearAlgebra.inv(m)
end

"""
    logdet(::AbstractMatrix)

Logarithm of the determinant of matrix ``\\mathbf{v}``.
"""
function logdet(v)
    return LinearAlgebra.logdet(v)
end

"""
    logfact(x)

Logarithm of the factorial of ``x``.
"""
function logfact(x)
    return log(factorial(x))
end

"""
    loggam(x)

Logarithm of the gamma function of ``x``.
"""
function loggam(x)
    return SpecialFunctions.loggamma(x)
end

"""
    mexp(x::AbstractMatrix)

Matrix exponential of ``\\mathbf{x}``.
"""
function mexp(x::AbstractMatrix)
    return exp(x)
end

"""
    phi(x)

Cumulative distribution function (CDF) of the standard normal distribution evaluated at ``x``.
"""
function phi(x)
    return cdf(Normal(), x)
end

"""
    probit

Inverse of [`phi`](@ref).
"""
function probit(e)
    return quantile(Normal(), e)
end

"""
    pow(a, b)

Return ``a`` raised to the power of ``b``.
"""
function pow(a, b)
    return a^b
end

"""
    rank(v::AbstractVector, i::Integer)

Return the rank of the ``i``-th element of ``\\mathbf{v}``.
"""
function rank(v::AbstractVector, i::Integer)
    return v[sortperm(v)[i]]
end

"""
    ranked(v::AbstractVector, i::Integer)

Return the ``i``-th element of ``\\mathbf{v}`` sorted in ascending order.
"""
function ranked(v::AbstractVector, i::Integer)
    return sort(v)[i]
end

"""
    sd(v::AbstractVector)

Return the standard deviation of the input vector ``\\mathbf{v}``.
"""
function sd(v::AbstractVector)
    return std(v)
end

"""
    softplus(x)

Return the softplus function of `x`, defined as ``\\log(1 + \\exp(x))``.
"""
function softplus(x)
    return LogExpFunctions.log1pexp(x)
end

"""
    _step(x)

Return 1 if ``x`` is greater than 0, and 0 otherwise.
"""
function _step(x)
    return ifelse(x > 0, 1.0, 0.0)
end

"""
    arcsin(x)

Return the arcsine of ``x``.
"""
function arcsin(x)
    return asin(x)
end

"""
    arcsinh(x)

Return the inverse hyperbolic sine of ``x``.
"""
function arcsinh(x)
    return asinh(x)
end

"""
    arccos(x)

Return the arccosine of ``x``.
"""
function arccos(x)
    return Base.Math.acos(x)
end

"""
    arccosh(x)

Return the inverse hyperbolic cosine of ``x``.
"""
function arccosh(x)
    return acosh(x)
end

"""
    arctan(x)

Return the arctangent of ``x``.
"""
function arctan(x)
    return atan(x)
end

"""
    arctanh(x)

See [`atanh`](@ref).
"""
function arctanh(x)
    return atanh(x)
end
