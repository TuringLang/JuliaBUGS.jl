"""
    abs(x)

Absolute value of `x`.
"""
function abs(x)
    return Base.abs(x)
end

"""
    cloglog(x)

Complementary log-log function of `x`. 

```math
cloglog(x) = log(-log(1 - x))
```
"""
function cloglog(x)
    return LogExpFunctions.cloglog(x)
end

"""
    equals(x, y)

Returns 1 if `x` is equal to `y`, 0 otherwise.
"""
function equals(x, y)
    return x == y ? 1 : 0
end

"""
    exp(x)

Exponential of `x`.
"""
function exp(x)
    return Base.Math.exp(x)
end

"""
    inprod(a, b)

Inner product of `a` and `b`.
"""
function inprod(a, b)
    return a * b
end

"""
    inverse(v)

Inverse of matrix `v`.
"""
function inverse(v)
    return LinearAlgebra.inv(v)
end

"""
    log(x)

Natural logarithm of `x`.
"""
function log(x)
    return Base.Math.log(x)
end

"""
    logdet(v)

Logarithm of the determinant of matrix `v`.
"""
function logdet(v)
    return LinearAlgebra.logdet(v)
end

"""
    logfact(x)

Logarithm of the factorial of `x`.
"""
function logfact(x)
    return log(factorial(x))
end

"""
    loggam(x)

Logarithm of the gamma function of `x`.
"""
function loggam(x)
    return SpecialFunctions.loggamma(x)
end

"""
    logit(x)

Logit function of `x`. 
    
```math
logit(x) = log(x / (1 - x))
```
"""
function logit(x)
    return LogExpFunctions.logit(x)
end

"""
    icloglog(x)

Inverse complementary log-log function of `x`. 

```math
icloglog(x) = 1 - exp(-exp(x))
```
"""
function icloglog(x)
    return LogExpFunctions.cexpexp(x)
end

"""
    logit(x)

Logit function of `x`. 
    
```math
logit(x) = log(x / (1 - x))
```
"""
function logistic(x)
    return LogExpFunctions.logistic(x)
end

"""
    mexp(x)

Matrix exponential of `x`.
"""
function mexp(x)
    return exp(x)
end

"""
    max(args...)

Return the maximum value of the input arguments.
"""
function max(args...)
    return Base.max(args...)
end

"""
    mean(v::AbstractVector)

Return the mean of the input vector `v`.
"""
function mean(v::AbstractVector)
    return Statistics.mean(v)
end

"""
    min(args...)

Return the minimum value of the input arguments.
"""
function min(args...)
    return Base.min(args...)
end

"""
    phi(x)

Cumulative distribution function (CDF) of the standard normal distribution evaluated at `x`.
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

Return `a` raised to the power of `b`.
"""
function pow(a, b)
    return a^b
end

"""
    sqrt(x)

Return the square root of `x`.
"""
function sqrt(x)
    return Base.Math.sqrt(x)
end

"""
    rank(v::Vector, i::Int)

Return the rank of the `i`-th element of `v`.
"""
function rank(v::Vector, i::Int)
    return v[sortperm(v)[i]]
end

"""
    ranked(v::Vector, i::Int)

Return the `i`-th element of `v` sorted in ascending order.
"""
function ranked(v::Vector, i::Int)
    return sort(v)[i]
end

"""
    round(x)

Round `x` to the nearest integer.
"""
function round(x)
    return Base.Math.round(x)
end

"""
    sd(v::Vector)

Return the standard deviation of the input vector `v`.
"""
function sd(v::Vector)
    return Statistics.std(v)
end

"""
    softplus(x)

Return the softplus function of `x`, defined as `log(1 + exp(x))`.
"""
function softplus(x)
    return LogExpFunctions.log1pexp(x)
end

"""
    sort(v::Vector)

Return a sorted copy of the input vector `v`.
"""
function sort(v::Vector)
    return Base.sort(v)
end

"""
    _step(x)

Return 1 if `x` is greater than 0, and 0 otherwise.
"""
function _step(x)
    return ifelse(x > 0, 1, 0)
end

"""
    sum(args...)

Return the sum of the input arguments.
"""
function sum(args...)
    return Base.sum(args...)
end

"""
    trunc(x)

Return the integer part of `x`.
"""
function trunc(x)
    return Base.Math.trunc(x)
end

"""
    sin(x)

Return the sine of `x`.
"""
function sin(x)
    return Base.Math.sin(x)
end

"""
    arcsin(x)

Return the arcsine of `x`.
"""
function arcsin(x)
    return Base.Math.asin(x)
end

"""
    arcsinh(x)

Return the inverse hyperbolic sine of `x`.
"""
function arcsinh(x)
    return Base.Math.asinh(x)
end

"""
    cos(x)

Return the cosine of `x`.
"""
function cos(x)
    return Base.Math.cos(x)
end

"""
    arccos(x)

Return the arccosine of `x`.
"""
function arccos(x)
    return Base.Math.acos(x)
end

"""
    arccosh(x)

Return the inverse hyperbolic cosine of `x`.
"""
function arccosh(x)
    return Base.Math.acosh(x)
end

"""
    tan(x)

Return the tangent of `x`.
"""
function tan(x)
    return Base.Math.tan(x)
end

"""
    arctan(x)

Return the arctangent of `x`.
"""
function arctan(x)
    return Base.Math.atan(x)
end

"""
    arctanh(x)

Return the inverse hyperbolic tangent of `x`.
"""
function arctanh(x)
    return Base.Math.atanh(x)
end
