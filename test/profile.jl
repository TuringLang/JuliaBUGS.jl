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

function benchmark_compile(name::Symbol)
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

    results = benchmark_compile(
        model_def, data, scalars, array_sizes, array_bitmap, merged_data
    )
    println("Benchmarking: $name")
    for (t, b) in results["analysis_passes"]
        println("\n\n")
        println(t, "\n")
        show(stdout, "text/plain", b)
    end
end

function benchmark_compile(
    model_def::Expr, data::NamedTuple, scalars, array_sizes, array_bitmap, merged_data
)
    suite = BenchmarkGroup()

    suite["analysis_passes"] = BenchmarkGroup([
        "CollectVariables", "DataTransformation", "NodeFunctions"
    ])

    suite["analysis_passes"]["CollectVariables"] = @benchmarkable analyze_program(
        CollectVariables(model_def, data), model_def, data
    )

    suite["analysis_passes"]["DataTransformation"] = @benchmarkable compute_data_transformation(
        scalars, array_sizes, model_def, data
    )

    suite["analysis_passes"]["NodeFunctions"] = @benchmarkable analyze_program(
        NodeFunctions(array_sizes, array_bitmap), model_def, merged_data
    )

    tune!(suite)
    results = run(suite; verbose=false)
    return results
end

for n in keys(BUGSExamples.VOLUME_I)
    benchmark_compile(n)
    println("\n\n")
end
