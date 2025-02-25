include("benchmark.jl")
using OrderedCollections

examples_to_benchmark = [
    :rats, :pumps, :bones, :oxford, :epil, :lsat, :schools, :beetles, :air
]

stan_results = Benchmark.benchmark_Stan_models(examples_to_benchmark)

juliabugs_models = [
    Benchmark._create_JuliaBUGS_model(model_name) for model_name in examples_to_benchmark
]
juliabugs_results = OrderedDict{Symbol,Benchmark.BenchmarkResult}()
for (model_name, model) in zip(examples_to_benchmark, juliabugs_models)
    @info "Benchmarking $model_name"
    juliabugs_results[model_name] = Benchmark.benchmark_JuliaBUGS_model(model)
end

println("### Stan results:")
Benchmark._print_results_table(stan_results; backend=Val(:markdown))
println("### JuliaBUGS results:")
Benchmark._print_results_table(juliabugs_results; backend=Val(:markdown))
