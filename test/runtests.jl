using UnPack
using Graphs, MetaGraphsNext
using Bijectors
using Setfield, BangBang
using Distributions
using DynamicPPL
using JuliaBUGS
using Test


@testset "JuliaBUGS.jl" begin
    include("turing_logp.jl")
end
