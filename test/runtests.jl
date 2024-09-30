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
using Graphs, MetaGraphsNext
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using MacroTools
using MCMCChains
using Random
using ReverseDiff

AbstractMCMC.setprogress!(false)

const Tests = ("elementary", "compilation", "profile", "gibbs", "mcmchains", "all")

const test_group = get(ENV, "TEST_GROUP", "all")
if test_group ∉ Tests
    error("Unknown test group: $test_group")
end

@info "Running tests for groups: $test_group"

if test_group == "elementary" || test_group == "all"
    @testset "Unit Tests" begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("utils.jl")
    end
    include("parser/test_parser.jl")
    include("passes.jl")
    include("graphs.jl")
end

if test_group == "compilation" || test_group == "all"
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
            model = compile(m.model_def, m.data, m.inits)
        end
    end
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
    end
    include("logp_tests/test_logp.jl")
end

if test_group == "profile" || test_group == "all"
    include("profiles/utils.jl")
    include("profiles/prof_compile_pass.jl")
    include("profiles/prof_logdensity.jl")
end

if test_group == "gibbs" || test_group == "all"
    include("gibbs.jl")
end

if test_group == "mcmchains" || test_group == "all"
    include("ext/mcmchains.jl")
end
