using JuliaBUGS
using JuliaBUGS: compile
# using BenchmarkTools
using JuliaBUGS.SemanticAnalysis:
    CompileState,
    determine_array_sizes!,
    concretize_colon_indexing!,
    compute_transformed!,
    check_multiple_assignments_pre_transform,
    check_multiple_assignments_post_transform!,
    build_eval_function

using JuliaBUGS:
    program!,
    CollectVariables,
    ConstantPropagation,
    PostChecking,
    NodeFunctions,
    merge_collections

##

m = :leuk
model_def = getfield(JuliaBUGS.BUGSExamples, m).model_def
data = getfield(JuliaBUGS.BUGSExamples, m).data
inits = getfield(JuliaBUGS.BUGSExamples, m).inits[1];

@benchmark begin
    scalars, array_sizes = program!(CollectVariables(), model_def, data)
    has_new_val, transformed_variables = program!(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    while has_new_val
        has_new_val, transformed_variables = program!(
            ConstantPropagation(false, transformed_variables), model_def, data
        )
    end
    array_bitmap, transformed_variables = program!(
        PostChecking(data, transformed_variables), model_def, data
    )
    merged_data = merge_collections(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = program!(
        NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
    )
end
#=
BenchmarkTools.Trial: 5 samples with 1 evaluation.
 Range (min … max):  1.059 s …   1.105 s  ┊ GC (min … max): 3.71% … 4.89%
 Time  (median):     1.070 s              ┊ GC (median):    4.99%
 Time  (mean ± σ):   1.077 s ± 19.562 ms  ┊ GC (mean ± σ):  4.67% ± 0.62%

  ██           █                    █                     █
  ██▁▁▁▁▁▁▁▁▁▁▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ ▁
  1.06 s         Histogram: frequency by time        1.11 s <

 Memory estimate: 338.48 MiB, allocs estimate: 5955349.
=#

@benchmark begin
    state = CompileState(model_def, data)
    determine_array_sizes!(state)
    concretize_colon_indexing!(state)
    check_multiple_assignments_pre_transform(state)
    compute_transformed!(state)
    # check_multiple_assignments_post_transform!(state)
end
#=
BenchmarkTools.Trial: 12 samples with 1 evaluation.
 Range (min … max):  383.590 ms … 461.347 ms  ┊ GC (min … max): 2.23% … 1.89%
 Time  (median):     414.902 ms               ┊ GC (median):    2.19%
 Time  (mean ± σ):   417.680 ms ±  19.629 ms  ┊ GC (mean ± σ):  2.33% ± 0.62%

  ▁           ▁       █▁  █  █         ▁     ▁                ▁
  █▁▁▁▁▁▁▁▁▁▁▁█▁▁▁▁▁▁▁██▁▁█▁▁█▁▁▁▁▁▁▁▁▁█▁▁▁▁▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ ▁
  384 ms           Histogram: frequency by time          461 ms <

 Memory estimate: 50.14 MiB, allocs estimate: 1022710.
=#

@benchmark begin
    all_vars, array_sizes = __determine_array_sizes(data)
    potential_conflict = __check_multiple_assignments(data, array_sizes)
    eval_env = JuliaBUGS.create_evaluate_env(all_vars, data, array_sizes)
    eval_env = __compute_transformed!(eval_env)
    JuliaBUGS.check_conflicts(eval_env, potential_conflict...)
end
#=
BenchmarkTools.Trial: 3131 samples with 1 evaluation.
 Range (min … max):  1.149 ms …  16.050 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.479 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.593 ms ± 677.442 μs  ┊ GC (mean ± σ):  2.69% ± 7.69%

    ▁▃▆██▇▆▅▂▁                                                ▁
  ▇████████████▇▆▅▇▇▆▇▆▅▁▃▃▃▆▁▅▅▃▁▃▄▅▃▄▃▄▁▁▆▅▅▁▃▁▃▃▅▃▃▄▅▄▆▇▆▄ █
  1.15 ms      Histogram: log(frequency) by time       4.2 ms <

 Memory estimate: 651.43 KiB, allocs estimate: 14947.
=#
