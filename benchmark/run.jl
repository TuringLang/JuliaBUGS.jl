using Pkg
Pkg.activate("./benchmark")
using OrderedCollections

include("benchmark.jl")

##
stan_results = Benchmark.benchmark_Stan_models()

##

all_juliabugs_model = [
    Benchmark._create_JuliaBUGS_model(model_name) for
    model_name in Benchmark.juliabugs_examples
]

juliabugs_results = OrderedDict{Symbol,Benchmark.BenchmarkResult}()
for (model_name, model) in zip(Benchmark.juliabugs_examples, all_juliabugs_model)
    @info "Benchmarking $model_name"
    try
        juliabugs_results[model_name] = Benchmark.benchmark_JuliaBUGS_model(model)
    catch e
        @warn "Model $model_name produces error: $e"
    end
end

# Benchmark.extract_median_time(juliabugs_results)

##

Benchmark._print_results_table(stan_results; backend=Val(:markdown))
println(Benchmark._print_results_table(juliabugs_results))
