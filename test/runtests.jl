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
using ChainRules
using DifferentiationInterface
using Distributions
using Graphs
using MetaGraphsNext
using LinearAlgebra
using LogDensityProblems
using LogDensityProblemsAD
using OrderedCollections
using MacroTools
using MCMCChains
using Mooncake: Mooncake
using Random
using ReverseDiff
using Serialization

AbstractMCMC.setprogress!(false)

const Tests = (
    "elementary",
    "compilation",
    "log_density",
    "gibbs",
    "mcmchains",
    "experimental",
    "source_gen",
    "all",
)

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
    include("model_macro.jl")
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
end

if test_group == "log_density" || test_group == "all"
    include("log_density.jl")
    include("model.jl")
end

if test_group == "gibbs" || test_group == "all"
    include("gibbs.jl")
end

if test_group == "mcmchains" || test_group == "all"
    include("ext/mcmchains.jl")
end

if test_group == "experimental" || test_group == "all"
    include("experimental/ProbabilisticGraphicalModels/bayesnet.jl")
end

if test_group == "source_gen" || test_group == "all"
    include("source_gen.jl")
end
