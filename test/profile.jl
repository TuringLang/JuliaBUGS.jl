using BenchmarkTools

using JuliaBUGS
using JuliaBUGS:
    BUGSExamples,
    analyze_program,
    CollectVariables,
    DataTransformation,
    NodeFunctions,
    compute_data_transformation

suite = BenchmarkGroup()

for name in keys(BUGSExamples.VOLUME_I)
    @info "Adding benchmark for $name"
    model_def = BUGSExamples.VOLUME_I[name].model_def
    data = BUGSExamples.VOLUME_I[name].data

    non_data_scalars, non_data_array_sizes = analyze_program(
        CollectVariables(model_def, data), model_def, data
    )
    eval_env = compute_data_transformation(
        non_data_scalars, non_data_array_sizes, model_def, data
    )

    _suite = BenchmarkGroup()
    _suite["CollectVariables"] = @benchmarkable analyze_program(
        CollectVariables($model_def, $data), $model_def, $data
    )
    _suite["DataTransformation"] = @benchmarkable compute_data_transformation(
        $non_data_scalars, $non_data_array_sizes, $model_def, $data
    )
    _suite["NodeFunctions"] = @benchmarkable analyze_program(
        NodeFunctions($non_data_array_sizes), $model_def, $eval_env
    )

    tune!(_suite)
    suite[string(name)] = _suite
end

results = run(suite; verbose=true)

function create_result_dict(results)
    result_dict = Dict{String,Dict{String,Dict{String,String}}}()
    for (name, example_suite) in results
        _d = Dict{String,Dict{String,String}}()
        for k in ("CollectVariables", "DataTransformation", "NodeFunctions")
            __d = Dict{String,String}()
            med = median(example_suite[k])
            min = minimum(example_suite[k])
            max = maximum(example_suite[k])
            for (str, val) in zip(["median", "minimum", "maximum"], [med, min, max])
                __d[str] = BenchmarkTools.prettytime(val.time)
            end
            __d["memory"] = BenchmarkTools.prettymemory(memory(example_suite[k]))
            _d[k] = __d
        end
        result_dict[name] = _d
    end
    return result_dict
end

function print_pure_text_table(result_dict)
    # Define the table header
    println(
        rpad("Example Name", 25),
        "|",
        lpad("Category", 20),
        "|",
        lpad("Median Time", 15),
        "|",
        lpad("Minimum Time", 15),
        "|",
        lpad("Maximum Time", 15),
        "|",
        lpad("Memory Usage", 15),
    )
    println("-"^105)  # Adjust the number based on the total length of the header

    # Iterate through each example and its benchmarks to populate the table rows
    for (name, benchmarks) in result_dict
        first_category = true
        for (category, results) in benchmarks
            if first_category
                println(
                    rpad(name, 25),
                    "|",
                    lpad(category, 20),
                    "|",
                    lpad(results["median"], 15),
                    "|",
                    lpad(results["minimum"], 15),
                    "|",
                    lpad(results["maximum"], 15),
                    "|",
                    lpad(results["memory"], 15),
                )
                first_category = false
            else
                println(
                    rpad("", 25),
                    "|",
                    lpad(category, 20),
                    "|",
                    lpad(results["median"], 15),
                    "|",
                    lpad(results["minimum"], 15),
                    "|",
                    lpad(results["maximum"], 15),
                    "|",
                    lpad(results["memory"], 15),
                )
            end
        end
        println("-"^105)  # Adjust the number based on the total length of the header
    end
end

function print_markdown_table_to_file(result_dict, filename=nothing)
    output_target = filename !== nothing ? open(filename, "w") : stdout

    try
        println(
            output_target,
            "| Example Name | Category | Median Time | Minimum Time | Maximum Time | Memory Usage |",
        )
        println(
            output_target,
            "|--------------|----------|-------------|--------------|--------------|--------------|",
        )

        for (name, benchmarks) in result_dict
            first_category = true
            for (category, results) in benchmarks
                if first_category
                    println(
                        output_target,
                        "| $(name) | $(category) | $(results["median"]) | $(results["minimum"]) | $(results["maximum"]) | $(results["memory"]) |",
                    )
                    first_category = false
                else
                    println(
                        output_target,
                        "|  | $(category) | $(results["median"]) | $(results["minimum"]) | $(results["maximum"]) | $(results["memory"]) |",
                    )
                end
            end
        end
    finally
        if filename !== nothing
            close(output_target)
        end
    end
end

result_dict = create_result_dict(results)
print_pure_text_table(result_dict)
