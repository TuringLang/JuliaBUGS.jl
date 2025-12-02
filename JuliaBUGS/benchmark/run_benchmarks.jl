include("benchmark.jl")

examples_to_benchmark = [
    :rats, :pumps, :bones, :oxford, :epil, :lsat, :schools, :beetles, :air
]

# Run Stan benchmarks (suppress stderr for download messages)
stan_results = redirect_stderr(devnull) do
    benchmark_Stan_models(examples_to_benchmark)
end

# Create JuliaBUGS models (suppress stderr for warnings)
juliabugs_models = redirect_stderr(devnull) do
    [
        JuliaBUGS.set_evaluation_mode(
            _create_JuliaBUGS_model(name), JuliaBUGS.UseGeneratedLogDensityFunction()
        ) for name in examples_to_benchmark
    ]
end

# Run JuliaBUGS benchmarks
juliabugs_results = OrderedDict{Symbol,BenchmarkResult}()
for (name, model) in zip(examples_to_benchmark, juliabugs_models)
    juliabugs_results[name] = benchmark_JuliaBUGS_model_with_Mooncake(model)
end

# Write markdown directly to file (not stdout)
output_file = get(ENV, "BENCHMARK_OUTPUT", "benchmark_results.md")
open(output_file, "w") do io
    println(io, "## Benchmark Results\n")
    cpu_info = first(Sys.cpu_info())
    println(io, "**Julia $(VERSION)** on $(cpu_info.model)\n")
    println(io, "Ratio = JuliaBUGS/Stan (lower is better for JuliaBUGS)\n")
    println(io, "| Model | Stan Params | JBUGS Params | LD Ratio | Grad Ratio |")
    println(io, "|:------|------------:|-------------:|---------:|-----------:|")
    for name in examples_to_benchmark
        stan = stan_results[name]
        jbugs = juliabugs_results[name]
        stan_ld, stan_grad = extract_median_time(stan)
        jbugs_ld, jbugs_grad = extract_median_time(jbugs)
        ld_ratio = jbugs_ld / stan_ld
        grad_ratio = jbugs_grad / stan_grad
        @printf(io, "| %s | %d | %d | %.2fx | %.2fx |\n", name, stan.dim, jbugs.dim, ld_ratio, grad_ratio)
    end
    println(
        io,
        "\n*Note: Performance comparison may not be apples-to-apples as parameter counts can differ due to different model parameterizations.*",
    )
end
