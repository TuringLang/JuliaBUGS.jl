using AbstractPPL
using Bijectors
using Documenter
using DynamicPPL
using JuliaBUGS
using Setfield
using Test
using UnPack

using DynamicPPL: getlogp, settrans!!

using JuliaBUGS:
    CollectVariables, program!, Var, Stochastic, Logical, evaluate!!, DefaultContext
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSPrimitives: mean

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
    # TODO: add more explicit tests for the parser
    include("bugsast.jl")
end

@testset "Compiler Passes" begin
    # TODO: test output of compiler passes, particularly the array size deduction, nested indexing
end

@testset "Compile $m" for m in [
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

@testset "Log Joint with DynamicPPL" begin
    include("run_logp_tests.jl")
end
