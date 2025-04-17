include("benchmark.jl")

examples_to_benchmark = [
    :rats, :pumps, :bones, :oxford, :epil, :lsat, :schools, :beetles, :air
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

# juliabugs_enzyme_results = OrderedDict{Symbol,BenchmarkResult}()
# for (model_name, model) in zip(examples_to_benchmark, juliabugs_models)
#     @info "Benchmarking $model_name with Enzyme"
#     try
#         juliabugs_enzyme_results[model_name] = benchmark_JuliaBUGS_model_with_Enzyme(model)
#     catch e
#         @warn "Error benchmarking $model_name with Enzyme: $e"
#     end
# end

println("### Stan results:")
_print_results_table(stan_results; backend=Val(:markdown))
println("### JuliaBUGS Mooncake results:")
_print_results_table(juliabugs_results; backend=Val(:markdown))
# println("### JuliaBUGS Enzyme results:")
# _print_results_table(juliabugs_enzyme_results; backend=Val(:markdown))
