using Distributions
using LinearAlgebra
using LogExpFunctions
using SpecialFunctions
using Statistics

include("functions.jl")
include("distributions.jl")

const INVERSE_LINK_FUNCTION = Dict(
    :logit => :logistic, :cloglog => :cexpexp, :log => :exp, :probit => :phi
)