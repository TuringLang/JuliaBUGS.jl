using Test
using MacroTools: @q
using JuliaBUGS
using Symbolics

include("bugsast.jl")
include("bugsmodel.jl")
# include("compiler.jl")
include("compiler_passes.jl")

@testset "JuliaBUGS.jl" begin
    # Write your tests here.
end
