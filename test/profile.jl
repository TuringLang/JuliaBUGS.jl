using BenchmarkTools

using JuliaBUGS
using JuliaBUGS:
    BUGSExamples,
    analyze_program,
    CollectVariables,
    DataTransformation,
    PostChecking,
    NodeFunctions,
    merge_with_coalescence,
    compute_data_transformation

suite = BenchmarkGroup()

for name in keys(BUGSExamples.VOLUME_I)
    @info "Adding benchmark for $name"
    model_def = BUGSExamples.VOLUME_I[name].model_def
    data = BUGSExamples.VOLUME_I[name].data

    scalars, array_sizes = analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    transformed_variables = compute_data_transformation(
        scalars, array_sizes, model_def, data
    )

    array_bitmap, transformed_variables = analyze_program(
        PostChecking(data, transformed_variables), model_def, data
    )
    merged_data = merge_with_coalescence(deepcopy(data), transformed_variables)

    vars, array_sizes, array_bitmap, node_args, node_functions, dependencies = analyze_program(
        NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
    )

    _suite = BenchmarkGroup()

    _suite["CollectVariables"] = @benchmarkable analyze_program(
        CollectVariables($model_def, $data), $model_def, $data
    )

    _suite["DataTransformation"] = @benchmarkable compute_data_transformation(
        $scalars, $array_sizes, $model_def, $data
    )

    _suite["NodeFunctions"] = @benchmarkable analyze_program(
        NodeFunctions($array_sizes, $array_bitmap), $model_def, $merged_data
    )

    tune!(_suite)
    suite[string(name)] = _suite
end

results = run(suite; verbose=true)

for (name, example_suite) in results
    println("\n")
    println(name)
    println("CollectVariables", example_suite["CollectVariables"])
    println("DataTransformation", example_suite["DataTransformation"])
    println("NodeFunctions", example_suite["NodeFunctions"])
end
