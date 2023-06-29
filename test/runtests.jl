using Bijectors
using Documenter
using DynamicPPL
using JuliaBUGS
using Setfield
using Test
using UnPack

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
            merge_dicts,
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

function compare_dppl_bugs_logps(dppl_model, bugs_model, transform=false)
    turing_logp = getlogp(
        last(
            DynamicPPL.evaluate!!(
                dppl_model,
                DynamicPPL.settrans!!(bugs_model.varinfo, transform),
                DynamicPPL.DefaultContext(),
            ),
        ),
    )
    bugs_logp = getlogp(
        evaluate!!(DynamicPPL.settrans!!(bugs_model, transform), JuliaBUGS.DefaultContext())
    )
    @test turing_logp ≈ bugs_logp atol = 1e-6
end

@testset "Log Joint with DynamicPPL" begin
    include("logp_dynamicppl/binomial.jl")
    include("logp_dynamicppl/gamma.jl")

    # include("logp_dynamicppl/blockers.jl")
    # include("logp_dynamicppl/bones.jl")
    # include("logp_dynamicppl/dogs.jl")
    include("logp_dynamicppl/rats.jl")
end
