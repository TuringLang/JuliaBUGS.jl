using UnPack
using Graphs, MetaGraphsNext
using Bijectors
using Setfield, BangBang
using Distributions
using DynamicPPL
using JuliaBUGS
using JuliaBUGS: create_BUGSGraph, create_varinfo, compile, merge_dicts
using JuliaBUGS: program!, CollectVariables, NodeFunctions
using LogDensityProblems, LogDensityProblemsAD
using Test

# TODO:
# 1. add unit tests and doctests
# 2. test JuliaBUGS under both transformed and untransformed
# 3. use some simpler examples to make sure the logp with falttened transformed parameters are correct
# 4. LogDensityProblems for dimension and gradients

@testset "JuliaBUGS.jl" begin
    include("turing_logp.jl")
end
