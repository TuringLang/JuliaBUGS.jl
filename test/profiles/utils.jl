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

function print_markdown_table(result_dict)
    print("\n\n")
    category_padding = maximum(length.(keys(result_dict))) + 5
    println(
        "| ",
        rpad("Example Name", 30),
        " | ",
        lpad("Category", category_padding),
        " | ",
        lpad("Median Time", 20),
        " | ",
        lpad("Minimum Time", 20),
        " | ",
        lpad("Maximum Time", 20),
        " | ",
        lpad("Memory Usage", 20),
        " |",
    )
    println(
        "|",
        "-"^32,
        "|",
        "-"^(category_padding + 2),
        "|",
        "-"^22,
        "|",
        "-"^22,
        "|",
        "-"^22,
        "|",
        "-"^22,
        "|",
    )

    for (name, benchmarks) in result_dict
        first_category = true
        for (category, results) in benchmarks
            if first_category
                println(
                    "| ",
                    rpad(name, 30),
                    " | ",
                    lpad(category, category_padding),
                    " | ",
                    lpad(results["median"], 20),
                    " | ",
                    lpad(results["minimum"], 20),
                    " | ",
                    lpad(results["maximum"], 20),
                    " | ",
                    lpad(results["memory"], 20),
                    " |",
                )
                first_category = false
            else
                println(
                    "| ",
                    rpad("", 30),
                    " | ",
                    lpad(category, category_padding),
                    " | ",
                    lpad(results["median"], 20),
                    " | ",
                    lpad(results["minimum"], 20),
                    " | ",
                    lpad(results["maximum"], 20),
                    " | ",
                    lpad(results["memory"], 20),
                    " |",
                )
            end
        end
    end
end
