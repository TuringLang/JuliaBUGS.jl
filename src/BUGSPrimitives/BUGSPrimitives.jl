module BUGSPrimitives

using Bijectors
using Distributions: cdf, quantile, Normal
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
    :cloglog,
    :cexpexp,
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
    :mexp,
    :max,
    :mean,
    :min,
    :phi,
    :probit,
    :pow,
    :sqrt,
    :rank,
    :ranked,
    :round,
    :sd,
    :softplus,
    :sort,
    :_step,
    :sum,
    :trunc,
    :sin,
    :cos,
    :tan,
    :arcsin,
    :arcsinh,
    :arccos,
    :arccosh,
    :arctan,
    :arctanh,
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
