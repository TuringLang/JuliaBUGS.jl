using JuliaBUGS
using JuliaBUGS: compile
using BenchmarkTools
using JuliaBUGS.SemanticAnalysis:
    CompileState,
    determine_array_sizes!,
    concretize_colon_indexing!,
    compute_transformed!,
    check_multiple_assignments_pre_transform,
    check_multiple_assignments_post_transform!,
    build_eval_function
using JuliaBUGS.GraphLib: build_dep_graph

##

# TODO: I am still facing world age problems, maybe just do opaque closure myself
# and simplify the eval_module to a simple struct

function semantic_analysis!(state)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)
    check_multiple_assignments_post_transform!(state)
    return state
end

m = :leuk
model_def = getfield(JuliaBUGS.BUGSExamples, m).model_def
data = getfield(JuliaBUGS.BUGSExamples, m).data
inits = getfield(JuliaBUGS.BUGSExamples, m).inits[1];

@time compile(model_def, data, inits)

@time begin
    state = CompileState(model_def, data)
    state = semantic_analysis!(state)
    build_dep_graph(state)
end
