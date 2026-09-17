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
    [_create_JuliaBUGS_model(name) for name in examples_to_benchmark]
end

# Run JuliaBUGS benchmarks
juliabugs_results = OrderedDict{Symbol,BenchmarkResult}()
fwddiff_results = OrderedDict{Symbol,BenchmarkResult}()
for (name, model) in zip(examples_to_benchmark, juliabugs_models)
    generated = JuliaBUGS.set_evaluation_mode(
        model, JuliaBUGS.UseGeneratedLogDensityFunction()
    )
    juliabugs_results[name] = benchmark_JuliaBUGS_model(
        generated, AutoMooncake(; config=nothing)
    )
    fwddiff_results[name] = benchmark_JuliaBUGS_model(model, AutoForwardDiff())
end

# Write markdown directly to file (not stdout)
output_file = get(ENV, "BENCHMARK_OUTPUT", "benchmark_results.md")
open(output_file, "w") do io
    println(io, "## Benchmark Results\n")
    cpu_info = first(Sys.cpu_info())
    os_info = Sys.KERNEL
    println(io, "**Julia $(VERSION)** on $(cpu_info.model) ($(os_info))\n")
    println(io, "Ratio = JuliaBUGS/Stan (lower is better for JuliaBUGS)\n")
    println(io, "`# Params` shows Stan / JuliaBUGS when parameter counts differ.\n")
    println(
        io,
        "Log Density uses generated evaluation. Gradient columns measure log density + gradient.\n",
    )
    println(
        io,
        "**McRvs** = Mooncake reverse mode with generated evaluation; **FwdDiff** = ForwardDiff with graph evaluation.\n",
    )
    println(io, "| Model | # Params | Log Density Ratio | McRvs Ratio | FwdDiff Ratio |")
    println(io, "|:------|---------:|------------------:|------------:|--------------:|")
    for name in examples_to_benchmark
        stan = stan_results[name]
        jbugs = juliabugs_results[name]
        params = stan.dim == jbugs.dim ? string(jbugs.dim) : "$(stan.dim) / $(jbugs.dim)"
        stan_ld, stan_grad = extract_median_time(stan)
        jbugs_ld, jbugs_grad = extract_median_time(jbugs)
        _, fwddiff_grad = extract_median_time(fwddiff_results[name])
        ld_ratio = jbugs_ld / stan_ld
        grad_ratio = jbugs_grad / stan_grad
        @printf(
            io,
            "| %s | %s | %.2fx | %.2fx | %.2fx |\n",
            name,
            params,
            ld_ratio,
            grad_ratio,
            fwddiff_grad / stan_grad
        )
    end
    println(
        io,
        "\n*Note: Stan benchmarks use hand-optimized Stan models, not direct BUGS translations. Comparison is illustrative only.*",
    )
end
