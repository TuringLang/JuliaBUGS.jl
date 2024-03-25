using JuliaBUGS:
    BUGSGraph, DefaultContext, evaluate!!, get_params_varinfo, LogDensityContext
using DynamicPPL: DynamicPPL, getlogp, settrans!!, SimpleVarInfo

@testset "Log joint probability" begin
    @testset "Single distribution models" begin
        @testset "$s" for s in [:binomial, :gamma, :lkj, :dwish, :ddirich]
            include(joinpath(dirname(@__FILE__), "/single_distribution_models/$s.jl"))
        end
    end
    @testset "BUGS models" begin
        @testset "$s" for s in [:blockers, :bones, :dogs, :rats]
            include(joinpath(dirname(@__FILE__), "/BUGS_models/$s.jl"))
        end
    end
end
