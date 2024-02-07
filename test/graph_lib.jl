using JuliaBUGS
using JuliaBUGS: SemanticAnalysis, GraphLib
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS.BUGSExamples: leuk, eyes
using JuliaBUGS.SemanticAnalysis:
    all_statements,
    CompileState,
    determine_array_sizes!,
    concretize_colon_indexing!,
    check_multiple_assignments_pre_transform,
    compute_transformed!
using JuliaBUGS.GraphLib:
    build_dependencies_eval_function, build_coarse_dep_graph, build_dep_graph
using MacroTools
using Test
using Graphs, MetaGraphsNext

using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)

##
@testset "build_coarse_dep_graph" begin
    ## for graph_lib
    model_def = leuk.model_def
    data = leuk.data
    state = SemanticAnalysis.CompileState(model_def, data)

    g = build_coarse_dep_graph(state)
end

@testset "build_dependencies_eval_function" begin
    # test 1
    model_def = leuk.model_def
    data = leuk.data
    state = CompileState(model_def, data)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)

    stmt = state.logical_for_statements[2]
    f_expr = build_dependencies_eval_function(state, stmt; return_expr=true)
    f = @RuntimeGeneratedFunction(f_expr)
    deps = JuliaBUGS.SemanticAnalysis.call(state.eval_module, f, 3, 4)
    @test deps == Any[(:Y, 3, 4), (:t, 5), (Symbol("obs.t"), 3), (:fail, 3)]

    # test 2
    model_def = eyes.model_def
    data = eyes.data
    state = CompileState(model_def, data)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)

    stmt = state.logical_for_statements[1]
    f_expr = build_dependencies_eval_function(state, stmt; return_expr=true)
    f = @RuntimeGeneratedFunction(f_expr)
    deps = JuliaBUGS.SemanticAnalysis.call(state.eval_module, f, 3)
    @test deps == Any[(:T, 3), (:lambda, 1:2)]
end

@testset "build_dep_graph" begin
    model_def = leuk.model_def
    data = leuk.data
    state = CompileState(model_def, data)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)

    g = build_dep_graph(state)

    @test !haskey(g, (:Y, 2, 3)) # transformed variables are not in the graph

    @test collect(inneighbor_labels(g, (Symbol("S.placebo"), 2))) ==
        [:beta, (:dL0, 1), (:dL0, 2)]

    @test collect(inneighbor_labels(g, (:Idt, 2, 3))) == [:beta, (:dL0, 3)]
end
