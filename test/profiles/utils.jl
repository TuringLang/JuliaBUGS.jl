function create_result_dict(results)
    result_dict = Dict{String,Dict{String,Dict{String,String}}}()
    for (name, example_suite) in results
        _d = Dict{String,Dict{String,String}}()
        for k in keys(example_suite)
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
