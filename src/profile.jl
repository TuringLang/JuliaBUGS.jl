using BenchmarkTools
using Profile, PProf

using JuliaBUGS
using JuliaBUGS:
    analyze_program,
    CollectVariables,
    ConstantPropagation,
    PostChecking,
    NodeFunctions,
    merge_with_coalescence

using JuliaBUGS.BUGSExamples: leuk, bones, epil
model_def = leuk.model_def
data = leuk.data
inits = leuk.inits[1]

# model_def = bones.model_def
# data = bones.data
# inits = bones.inits[1]

# model_def = epil.model_def
# data = epil.data
# inits = epil.inits[1]

## 

@benchmark begin
    scalars, array_sizes = analyze_program(CollectVariables(), model_def, data)
    has_new_val, transformed_variables = analyze_program(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    while has_new_val
        has_new_val, transformed_variables = analyze_program(
            ConstantPropagation(false, transformed_variables), model_def, data
        )
    end
    array_bitmap, transformed_variables = analyze_program(
        PostChecking(data, transformed_variables), model_def, data
    )
    merged_data = merge_with_coalescence(deepcopy(data), transformed_variables)
    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = analyze_program(
        NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
    )
end

@benchmark has_new_val, transformed_variables = analyze_program(
    ConstantPropagation(scalars, array_sizes), model_def, data
)
Profile.clear()
@profile analyze_program(ConstantPropagation(scalars, array_sizes), model_def, data)
pprof()

@benchmark begin
    has_new_val, transformed_variables = analyze_program(
        ConstantPropagation(scalars, array_sizes), model_def, data
    )
    while has_new_val
        has_new_val, transformed_variables = analyze_program(
            ConstantPropagation(false, transformed_variables), model_def, data
        )
    end
end

VSCodeServer.@profview analyze_program(ConstantPropagation(scalars, array_sizes), model_def, data)

@benchmark analyze_program(PostChecking(data, transformed_variables), model_def, data)

@benchmark merge_with_coalescence(deepcopy(data), transformed_variables)

@benchmark analyze_program(NodeFunctions(array_sizes, array_bitmap), model_def, merged_data)
VSCodeServer.@profview analyze_program(
    NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
)
