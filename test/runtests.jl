using AbstractPPL
using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using Bijectors
using Distributions
using Documenter
using DynamicPPL
using DynamicPPL: getlogp, settrans!!, SimpleVarInfo
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
using Setfield
using Test
using UnPack

AbstractMCMC.setprogress!(false)

if get(ENV, "RUN_MODE", "test") == "profile"
    include("profile.jl")
else
    @testset "Function Unit Tests" begin
        DocMeta.setdocmeta!(
            JuliaBUGS,
            :DocTestSetup,
            :(using JuliaBUGS:
                JuliaBUGS,
                BUGSExamples,
                @bugs,
                evaluate_and_track_dependencies,
                evaluate,
                concretize_colon_indexing,
                extract_variable_names_and_numdims,
                extract_variables_in_bounds_and_lhs_indices,
                simple_arithmetic_eval);
            recursive=true,
        )
        Documenter.doctest(JuliaBUGS; manual=false)
    end

    include("bugs_primitives.jl")

    @testset "Parser" begin
        include("parser/bugs_macro.jl")
        include("parser/bugs_parser.jl")
        include("parser/winbugs_examples.jl")
    end

    include("compile.jl")

    include("cumulative_density.jl")

    @testset "Compile WinBUGS Vol I examples: $m" for m in [
        :blockers,
        :bones,
        :dogs,
        :dyes,
        :epil,
        :equiv,
        :kidney,
        :leuk,
        :leukfr,
        :lsat,
        :magnesium,
        :mice,
        :oxford,
        :pumps,
        :rats,
        :salm,
        :seeds,
        :stacks,
        :surgical_simple,
        :surgical_realistic,
    ]
        model_def = JuliaBUGS.BUGSExamples.VOLUME_I[m].model_def
        data = JuliaBUGS.BUGSExamples.VOLUME_I[m].data
        inits = JuliaBUGS.BUGSExamples.VOLUME_I[m].inits[1]
        model = compile(model_def, data, inits)
    end

    @testset "Utils" begin
        include("utils.jl")
    end

    include("passes.jl")

    @testset "Log Probability Test" begin
        include("run_logp_tests.jl")
        @testset "Single stochastic variable test" begin
            @testset "test for $s" for s in [:binomial, :gamma, :lkj, :dwish, :ddirich]
                include("logp_tests/$s.jl")
            end
        end
        @testset "BUGS examples" begin
            @testset "test for $s" for s in [:blockers, :bones, :dogs, :rats]
                include("logp_tests/$s.jl")
            end
        end
    end

    @testset "Graph data structure" begin
        include("graphs.jl")
    end

    include("gibbs.jl")

    include("ext/mcmchains.jl")
end
