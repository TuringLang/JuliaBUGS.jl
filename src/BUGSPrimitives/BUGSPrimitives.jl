module BUGSPrimitives

using Distributions
using LinearAlgebra
using LogExpFunctions
using Random
using SpecialFunctions
using Statistics
import InverseFunctions

include("functions.jl")
include("distributions.jl")

InverseFunctions.inverse(::typeof(phi)) = probit
InverseFunctions.inverse(::typeof(probit)) = phi

end
