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
    "profile",
    "unit",
    "parser",
    "analysis_passes",
    "compile_BUGS_examples",
    "corner_cases",
    "graph",
    "logp",
    "gibbs",
    "mcmchains",
)

for arg in ARGS
    if arg ∉ Tests
        error("Unknown test group: $arg")
    end
end

@info "Running tests for groups: $(ARGS)"

if "profile" in ARGS
    include("profile.jl")
elseif "unit" in ARGS
    @testset "Unit Tests" begin
        Documenter.doctest(JuliaBUGS; manual=false)
        include("utils.jl")
    end
elseif "parser" in ARGS
    include("parser/test_parser.jl")
elseif "analysis_passes" in ARGS
    include("passes.jl")
elseif "compile_BUGS_examples" in ARGS
    @testset "BUGS examples volume 1" begin
        @testset "$m" for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
            m = JuliaBUGS.BUGSExamples.VOLUME_1[m]
            model = compile(m.model_def, m.data, m.inits[1])
        end
    end
elseif "corner_cases" in ARGS
    @testset "Some corner cases" begin
        include("bugs_primitives.jl")
        include("compile.jl")
        include("cumulative_density.jl")
    end
elseif "graph" in ARGS
    include("graphs.jl")
elseif "logp" in ARGS
    include("logp_tests/test_logp.jl")
elseif "gibbs" in ARGS
    include("gibbs.jl")
elseif "mcmchains" in ARGS
    include("ext/mcmchains.jl")
else # run all
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
