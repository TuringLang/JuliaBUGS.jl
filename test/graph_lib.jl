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
using JuliaBUGS.GraphLib: build_dependencies_eval_function, build_dep_graph
using MacroTools
using Test
using Graphs, MetaGraphsNext

using RuntimeGeneratedFunctions
RuntimeGeneratedFunctions.init(@__MODULE__)
##
@testset "build_dependencies_eval_function" begin
    # test 1
    model_def = leuk.model_def
    data = leuk.data
    state = CompileState(model_def, data)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)
    for k in keys(state.array_sizes)
        if k ∉ state.variables_tracked_in_eval_module
            @eval state.eval_module $k = $(fill(missing, state.array_sizes[k]...))
        end
    end

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
    for k in keys(state.array_sizes)
        if k ∉ state.variables_tracked_in_eval_module
            @eval state.eval_module $k = $(fill(missing, state.array_sizes[k]...))
        end
    end

    stmt = state.logical_for_statements[1]
    f_expr = build_dependencies_eval_function(state, stmt; return_expr=true)
    f = @RuntimeGeneratedFunction(f_expr)
    deps = JuliaBUGS.SemanticAnalysis.call(state.eval_module, f, 3)
    @test deps == Any[(:T, 3), (:lambda, 1:2)]
end

model_def = leuk.model_def
data = leuk.data
state = CompileState(model_def, data)
determine_array_sizes!(state)
concretize_colon_indexing!(state)
check_multiple_assignments_pre_transform(state)
compute_transformed!(state)
for k in keys(state.array_sizes)
    if k ∉ state.variables_tracked_in_eval_module
        @eval state.eval_module $k = $(fill(missing, state.array_sizes[k]...))
    end
end
scalars = Set()
for stmt in all_statements(state)
    for rhs_var in stmt.rhs_vars
        if rhs_var ∉ keys(state.array_sizes)
            push!(scalars, rhs_var)
        end
    end
end
for scalar in scalars
    if scalar ∉ state.variables_tracked_in_eval_module
        @eval state.eval_module $scalar = missing
    end
end

g = build_dep_graph(state)

labels(g) |> collect

collect(edge_labels(g))

outneighbor_labels(g, (:Y, 2, 3)) |> collect

inneighbor_labels(g, (Symbol("S.placebo"), 2)) |> collect

state.eval_module.beta



stmt = state.logical_for_statements[end]
    f_expr = build_dependencies_eval_function(state, stmt; return_expr=true)
    f = @RuntimeGeneratedFunction(f_expr)
    deps = JuliaBUGS.SemanticAnalysis.call(state.eval_module, f, 3)
    @test deps == Any[(:Y, 3, 4), (:t, 5), (Symbol("obs.t"), 3), (:fail, 3)]