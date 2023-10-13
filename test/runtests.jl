using AbstractPPL
using AbstractMCMC
using AdvancedHMC
using AdvancedMH
using Bijectors
using Distributions
using Documenter
using DynamicPPL
using DynamicPPL: getlogp, settrans!!
using Graphs, MetaGraphsNext
using JuliaBUGS
using JuliaBUGS:
    CollectVariables,
    program!,
    Var,
    Stochastic,
    Logical,
    evaluate!!,
    DefaultContext,
    BUGSGraph,
    stochastic_neighbors,
    stochastic_inneighbors,
    stochastic_outneighbors,
    markov_blanket,
    MarkovBlanketCoveredBUGSModel,
    evaluate!!,
    LogDensityContext,
    ConcreteNodeInfo,
    SimpleVarInfo,
    get_params_varinfo
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

Random.seed!(12345)

@testset "Function Unit Tests" begin
    DocMeta.setdocmeta!(
        JuliaBUGS,
        :DocTestSetup,
        :(using JuliaBUGS:
            Var,
            create_array_var,
            replace_constants_in_expr,
            evaluate_and_track_dependencies,
            find_variables_on_lhs,
            evaluate,
            merge_collections,
            scalarize,
            concretize_colon_indexing,
            check_unresolved_indices,
            check_out_of_bounds,
            check_implicit_indexing,
            check_partial_missing_values);
        recursive=true,
    )
    Documenter.doctest(JuliaBUGS; manual=false)
end

@testset "Parser" begin
    include("bugsast.jl")
    include("parser.jl")
end

@testset "Compilation" begin
    include("compile.jl")
end

@testset "Compile $m" for m in [
    :blockers,
    :bones,
    :dogs,
    :dyes,
    :epil,
    :equiv,
    :kidney,
    # :leuk, # leuk requires higher-level of constant propagation, particularly dN is transformed variable, but only if Y is figured out first
    # :leukfr, # similar reason to `leuk`
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

@testset "Markov Blanket" begin
    include("graphs.jl")
end

include("mcmchains.jl")
