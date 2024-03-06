"""
    abs(x)

Absolute value of `x`.
"""
abs

"""
    cloglog(x)

Complementary log-log function of `x`. Can be used as link function.

```math
\\log{(-\\log{(1 - x)})}
```
"""
function cloglog(x)
    return LogExpFunctions.cloglog(x)
end

"""
    cexpexp(x)

Complementary exponential of the complementary exponential of `x`.

```math
1 - \\exp{(-\\exp{(x)})}
```
"""
function cexpexp(x)
    return LogExpFunctions.cexpexp(x)
end

"""
    equals(x, y)

Returns 1 if ``x`` is equal to ``y``, 0 otherwise.
"""
function equals(x, y)
    return x == y ? 1 : 0
end

"""
    exp(x)

Exponential of ``x``.
"""
exp

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
    log(x)

Natural logarithm of ``x``.
"""
log

"""
    logdet(::AbstractMatrix)

Logarithm of the determinant of matrix ``\\mathbf{v}``.
"""
function logdet(v::AbstractMatrix)
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
    logit(x)

Logit function of ``x``. 
    
```math
\\log{(\\frac{x}{1 - x})}
```
"""
function logit(x)
    return LogExpFunctions.logit(x)
end

"""
    logistic(x)

Logistic function of ``x``.
    
```math
\\frac{1}{1 + \\exp{(-x)}}
```
"""
function logistic(x)
    return LogExpFunctions.logistic(x)
end

"""
    mexp(x::AbstractMatrix)

Matrix exponential of ``\\mathbf{x}``.
"""
function mexp(x::AbstractMatrix)
    return exp(x)
end

"""
    max(args...)

Return the maximum value of the input arguments.
"""
max

"""
    mean(v::AbstractVector)

Return the mean of the input vector ``\\mathbf{v}``.
"""
mean

"""
    min(args...)

Return the minimum value of the input arguments.
"""
min

"""
    phi(x)

Cumulative distribution function (CDF) of the standard normal distribution evaluated at ``x``.
"""
function phi(x)
    return Distributions.cdf(Distributions.Normal(0, 1), x)
end

"""
    probit

Inverse of [`phi`](@ref).
"""
function probit(e)
    return quantile(Normal(0, 1), e)
end

"""
    pow(a, b)

Return ``a`` raised to the power of ``b``.
"""
function pow(a, b)
    return a^b
end

"""
    sqrt(x)

Return the square root of ``x``.
"""
sqrt

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
    round(x)

Round ``x`` to the nearest Integereger.
"""
round

"""
    sd(v::AbstractVector)

Return the standard deviation of the input vector ``\\mathbf{v}``.
"""
function sd(v::AbstractVector)
    return Statistics.std(v)
end

"""
    softplus(x)

Return the softplus function of `x`, defined as ``\\log(1 + \\exp(x))``.
"""
function softplus(x)
    return LogExpFunctions.log1pexp(x)
end

"""
    sort(v::AbstractVector)

Return a sorted copy of the input vector `v`.
"""
sort

"""
    _step(x)

Return 1 if ``x`` is greater than 0, and 0 otherwise.
"""
function _step(x)
    return ifelse(x > 0, 1.0, 0.0)
end

"""
    sum(args...)

Return the sum of the input arguments.
"""
sum

"""
    trunc(x)

Return the Integereger part of ``x``.
"""
trunc

"""
    sin(x)

Return the sine of ``x``.
"""
sin

"""
    arcsin(x)

Return the arcsine of ``x``.
"""
function arcsin(x)
    return Base.Math.asin(x)
end

"""
    arcsinh(x)

Return the inverse hyperbolic sine of ``x``.
"""
function arcsinh(x)
    return Base.Math.asinh(x)
end

"""
    cos(x)

Return the cosine of ``x``.
"""
cos

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
    return Base.Math.acosh(x)
end

"""
    tan(x)

Return the tangent of ``x``.
"""
tan

"""
    arctan(x)

Return the arctangent of ``x``.
"""
function arctan(x)
    return Base.Math.atan(x)
end

"""
    arctanh(x)

Return the inverse hyperbolic tangent of ``x``.
"""
function arctanh(x)
    return Base.Math.atanh(x)
end
