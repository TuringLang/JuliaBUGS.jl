module ProbabilisticGraphicalModels

using BangBang
using Graphs
using MetaGraphsNext
using Distributions
using JuliaBUGS
using JuliaBUGS: BUGSGraph, VarName, NodeInfo
using AbstractPPL
using Bijectors: Bijectors
using LinearAlgebra: Cholesky
using LogExpFunctions

include("bayesian_network.jl")
include("conditioning.jl")
include("functions.jl")
end
