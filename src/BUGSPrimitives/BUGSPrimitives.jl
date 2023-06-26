module BUGSPrimitives

using Distributions
using LinearAlgebra
using LogExpFunctions
using Random
using SpecialFunctions
using Statistics
using InverseFunctions: InverseFunctions

include("functions.jl")
include("distributions.jl")

InverseFunctions.inverse(::typeof(phi)) = probit
InverseFunctions.inverse(::typeof(probit)) = phi

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
