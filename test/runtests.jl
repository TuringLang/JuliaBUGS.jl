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
    BUGSGraph,
    CollectVariables,
    ConcreteNodeInfo,
    ConstantPropagation,
    DefaultContext,
    evaluate!!,
    get_params_varinfo,
    Logical,
    LogDensityContext,
    merge_collections,
    MHFromPrior,
    NodeFunctions,
    PostChecking,
    program!,
    SimpleVarInfo,
    Stochastic,
    stochastic_inneighbors,
    stochastic_neighbors,
    stochastic_outneighbors,
    markov_blanket,
    Var,
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

include("bugs_primitives.jl")

@testset "Parser" begin
    include("parser/bugs_macro.jl")
    include("parser/bugs_parser.jl")
    include("parser/winbugs_examples.jl")
end

include("compile.jl")

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
