using SymbolicPPL
using Symbolics
using Test
using MacroTools: @q

include("bugsast.jl")
include("bugsmodel.jl")
include("compiler.jl")

using JuliaBUGS

@testset "JuliaBUGS.jl" begin
    # Write your tests here.
end