include("benchmark.jl")

examples_to_benchmark = [
    :rats, :pumps, :bones, :oxford, :epil, :lsat, :schools, :beetles, :air
]

examples_to_benchmark_full = [
    :rats,
    :pumps,
    :seeds,
    :surgical_realistic,
    :magnesium,
    :salm,
    :equiv,
    :dyes,
    :stacks,
    :epil,
    :blockers,
    :oxford,
    :lsat,
    :bones,
    :mice,
    :kidney,
    :leuk,
    :leukfr,
    :dugongs,
    :air,
    :birats,
    :schools,
    :beetles,
    :alligators,
]

stan_results = benchmark_Stan_models(examples_to_benchmark)

juliabugs_models = [
    JuliaBUGS.set_evaluation_mode(
        _create_JuliaBUGS_model(model_name), JuliaBUGS.UseGeneratedLogDensityFunction()
    ) for model_name in examples_to_benchmark
]
juliabugs_results = OrderedDict{Symbol,BenchmarkResult}()
for (model_name, model) in zip(examples_to_benchmark, juliabugs_models)
    @info "Benchmarking $model_name with Mooncake"
    juliabugs_results[model_name] = benchmark_JuliaBUGS_model_with_Mooncake(model)
end

println("### Stan results:")
_print_results_table(stan_results; backend=:markdown)

println("### JuliaBUGS Mooncake results:")
_print_results_table(juliabugs_results; backend=:markdown)
