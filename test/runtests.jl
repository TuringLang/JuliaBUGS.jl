using AbstractPPL
using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using Bijectors
using Distributions
using Documenter
using DynamicPPL: DynamicPPL, getlogp, settrans!!, SimpleVarInfo
using Graphs, MetaGraphsNext
using JuliaBUGS
using JuliaBUGS:
    BUGSGraph,
    DefaultContext,
    evaluate!!,
    get_params_varinfo,
    LogDensityContext,
    MHFromPrior,
    stochastic_inneighbors,
    stochastic_neighbors,
    stochastic_outneighbors,
    markov_blanket,
    Gibbs
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSPrimitives: mean
using LinearAlgebra
using LogDensityProblems, LogDensityProblemsAD
using MacroTools
using MCMCChains
using Random
using ReverseDiff
using Test

AbstractMCMC.setprogress!(false)

const test_group = get(ENV, "TEST_GROUP", "run_all")

if test_group == "profile"
    include("profile.jl")
elseif test_group == "unit"
    @testset "doctests" begin
        DocMeta.setdocmeta!(JuliaBUGS, :DocTestSetup, :(using JuliaBUGS); recursive=true)
        Documenter.doctest(JuliaBUGS; manual=false)
    end
    include("utils.jl")
elseif test_group == "parser"
    @testset "Parser" begin
        include("parser/bugs_macro.jl")
        include("parser/bugs_parser.jl")
        include("parser/winbugs_examples.jl")
    end
elseif test_group == "analysis_passes"
    include("passes.jl")
elseif test_group == "compile_BUGS_examples"
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            model_def = JuliaBUGS.BUGSExamples.VOLUME_1[m].model_def
            data = JuliaBUGS.BUGSExamples.VOLUME_1[m].data
            inits = JuliaBUGS.BUGSExamples.VOLUME_1[m].inits[1]
            model = compile(model_def, data, inits)
        end
    end
elseif test_group == "corner_cases"
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
        include("cumulative_density.jl")
    end
elseif test_group == "graph"
    include("graphs.jl")
elseif test_group == "gibbs"
    include("gibbs.jl")
elseif test_group == "mcmchains"
    include("ext/mcmchains.jl")
else # run all
    include("profile.jl")
    @testset "doctests" begin
        DocMeta.setdocmeta!(JuliaBUGS, :DocTestSetup, :(using JuliaBUGS); recursive=true)
        Documenter.doctest(JuliaBUGS; manual=false)
    end
    include("utils.jl")
    @testset "Parser" begin
        include("parser/bugs_macro.jl")
        include("parser/bugs_parser.jl")
        include("parser/winbugs_examples.jl")
    end
    include("passes.jl")
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            model_def = JuliaBUGS.BUGSExamples.VOLUME_1[m].model_def
            data = JuliaBUGS.BUGSExamples.VOLUME_1[m].data
            inits = JuliaBUGS.BUGSExamples.VOLUME_1[m].inits[1]
            model = compile(model_def, data, inits)
        end
    end
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
        include("cumulative_density.jl")
    end
    include("graphs.jl")
    include("gibbs.jl")
    include("ext/mcmchains.jl")
end
