using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using Documenter
using Test
using JuliaBUGS.BUGSPrimitives: mean
DocMeta.setdocmeta!(JuliaBUGS, :DocTestSetup, :(using JuliaBUGS); recursive=true)

using AbstractPPL
using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using Bijectors
using Distributions
using Graphs
using MetaGraphsNext
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using MacroTools
using MCMCChains
using Random
using ReverseDiff

AbstractMCMC.setprogress!(false)

const Tests = (
    "--elementary",
    "--compilation",
    "--profile",
    "--gibbs",
    "--mcmchains",
)

for arg in ARGS
    if arg ∉ Tests
        error("Unknown test group: $arg")
    end
end

@info "Running tests for groups: $(ARGS)"

if "--elementary" in ARGS
    @testset "Unit Tests" begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("utils.jl")
    end
    include("parser/test_parser.jl")
    include("passes.jl")
    include("graphs.jl")
end

if "--compilation" in ARGS
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
            model = compile(m.model_def, m.data, m.inits[1])
        end
    end
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
        include("cumulative_density.jl")
    end
    include("logp_tests/test_logp.jl")
end

if "--profile" in ARGS
    include("profile.jl")
end

if "--gibbs" in ARGS
    include("gibbs.jl")
end

if "--mcmchains" in ARGS
    include("ext/mcmchains.jl")
end

if isempty(ARGS) # run all
    @testset "Unit Tests" begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("utils.jl")
    end
    include("parser/test_parser.jl")
    include("passes.jl")
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
            model = compile(m.model_def, m.data, m.inits[1])
        end
    end
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
        include("cumulative_density.jl")
    end
    include("graphs.jl")
    include("logp_tests/test_logp.jl")
    include("gibbs.jl")
    include("ext/mcmchains.jl")
end
