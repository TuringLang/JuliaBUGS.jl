module BUGSPrimitives

using Bijectors: Bijectors
using Distributions: Distributions
using LinearAlgebra
using LogExpFunctions: cloglog, cexpexp, logit, logistic
using PDMats
using Random
using SpecialFunctions
using Statistics: mean, std

include("functions.jl")
include("distributions.jl")

"""
    _inv(m::AbstractMatrix)

Matrix inverse using `cholesky_lower` to avoid issue with ReverseDiff.
"""
function _inv(m::AbstractMatrix)
    L = Bijectors.cholesky_lower(m)
    inv_L = inv(L)
    return inv_L' * inv_L
end

const BUGS_FUNCTIONS = (
    :abs,
    :acos,
    :acosh,
    :arccos,
    :arccosh,
    :asin,
    :asinh,
    :arcsin,
    :arcsinh,
    :atan,
    :atanh,
    :arctan,
    :arctanh,
    :cexpexp,
    :cloglog,
    :cos,
    :equals,
    :exp,
    :icloglog,
    :ilogit,
    :inprod,
    :inverse,
    :log,
    :logdet,
    :logfact,
    :loggam,
    :logit,
    :logistic,
    :max,
    :mean,
    :min,
    :mexp,
    :phi,
    :pow,
    :probit,
    :rank,
    :ranked,
    :round,
    :sd,
    :sin,
    :softplus,
    :sort,
    :sqrt,
    :sum,
    :_step,
    :tan,
    :trunc,
)

const BUGS_DISTRIBUTIONS = [
    :dnorm,
    :dlogis,
    :dt,
    :ddexp,
    :dflat,
    :dexp,
    :dchisqr,
    :dweib,
    :dlnorm,
    :dgamma,
    :dpar,
    :dgev,
    :dgpar,
    :df,
    :dunif,
    :dbeta,
    :dmnorm,
    :dmt,
    :dwish,
    :ddirich,
    :dbern,
    :dbin,
    :dcat,
    :dpois,
    :dgeom,
    :dnegbin,
    :dbetabin,
    :dhyper,
    :dmulti,
    :TDistShiftedScaled,
    :Flat,
    :LeftTruncatedFlat,
    :RightTruncatedFlat,
    :TruncatedFlat,
]

# functions
export cloglog,
    cexpexp,
    equals,
    icloglog,
    ilogit,
    inprod,
    inverse,
    logdet,
    logfact,
    loggam,
    logit,
    logistic,
    mexp,
    mean,
    phi,
    probit,
    pow,
    rank,
    ranked,
    sd,
    softplus,
    _step,
    arcsin,
    arcsinh,
    arccos,
    arccosh,
    arctan,
    arctanh

# distributions
export dnorm,
    dlogis,
    dt,
    ddexp,
    dflat,
    dexp,
    dchisqr,
    dweib,
    dlnorm,
    dgamma,
    dpar,
    dgev,
    dgpar,
    df,
    dunif,
    dbeta,
    dmnorm,
    dmt,
    dwish,
    ddirich,
    dbern,
    dbin,
    dcat,
    dpois,
    dgeom,
    dnegbin,
    dbetabin,
    dhyper,
    dmulti,
    TDistShiftedScaled,
    Flat,
    LeftTruncatedFlat,
    RightTruncatedFlat,
    TruncatedFlat

end
