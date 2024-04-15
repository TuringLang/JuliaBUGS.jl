using BenchmarkTools

using JuliaBUGS
using JuliaBUGS: BUGSExamples

suite = BenchmarkGroup()

for name in keys(BUGSExamples.VOLUME_1)
    @info "Adding benchmark for $name"
    model_def = BUGSExamples.VOLUME_1[name].model_def
    data = BUGSExamples.VOLUME_1[name].data

    non_data_scalars, non_data_array_sizes = JuliaBUGS.determine_array_sizes(
        model_def, data
    )

    eval_env = JuliaBUGS.compute_data_transformation(
        non_data_scalars, non_data_array_sizes, model_def, data
    )

    _suite = BenchmarkGroup()

    _suite["CollectVariables"] = @benchmarkable JuliaBUGS.determine_array_sizes(
        $model_def, $data
    )

    _suite["DataTransformation"] = @benchmarkable JuliaBUGS.compute_data_transformation(
        $non_data_scalars, $non_data_array_sizes, $model_def, $data
    )

    model_def = JuliaBUGS.concretize_colon_indexing(model_def, eval_env)
    _suite["GraphCreation"] = @benchmarkable JuliaBUGS.create_graph($model_def, $eval_env)

    tune!(_suite)
    suite[string(name)] = _suite
end

results = run(suite; verbose=false)
result_dict = create_result_dict(results)
print_markdown_table(result_dict)
