include("benchmark.jl")
using OrderedCollections
using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using JuliaBUGS: phi
using JuliaBUGS: Bijectors
using JuliaBUGS.Distributions

examples_to_benchmark = [
    :rats, :pumps, :oxford, :epil, :lsat, :schools, :beetles, :air
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

juliabugs_source_gen_mooncake_results = OrderedDict{Symbol,Benchmark.BenchmarkResult}()
for (i, model_name) in enumerate(examples_to_benchmark)
    @info "Benchmarking $model_name"
    model = juliabugs_models[i]
    evaluation_env = deepcopy(model.evaluation_env)
    lowered_model_def = JuliaBUGS._generate_lowered_model_def(model, evaluation_env)
    expr = JuliaBUGS._gen_log_density_computation_function_expr(lowered_model_def, evaluation_env)
    log_density_eval_function = eval(expr)
    juliabugs_source_gen_mooncake_results[model_name] = Benchmark.benchmark_JuliaBUGS_source_gen(
        model, log_density_eval_function; backend_str=:Mooncake
    )
end

juliabugs_source_gen_enzyme_results = OrderedDict{Symbol,Benchmark.BenchmarkResult}()
for (i, model_name) in enumerate(examples_to_benchmark)
    @info "Benchmarking $model_name"
    model = juliabugs_models[i]
    evaluation_env = deepcopy(model.evaluation_env)
    lowered_model_def = JuliaBUGS._generate_lowered_model_def(model, evaluation_env)
    expr = JuliaBUGS._gen_log_density_computation_function_expr(lowered_model_def, evaluation_env)
    log_density_eval_function = eval(expr)
    try
        juliabugs_source_gen_enzyme_results[model_name] = Benchmark.benchmark_JuliaBUGS_source_gen(
            model, log_density_eval_function; backend_str=:Enzyme
        )
    catch e
        @warn "Error benchmarking $model_name: $e"
    end
end

println("### Stan results:")
Benchmark._print_results_table(stan_results; backend=Val(:markdown))
println("### JuliaBUGS results:")
Benchmark._print_results_table(juliabugs_results; backend=Val(:markdown))
println("### JuliaBUGS source gen (Mooncake) results:")
Benchmark._print_results_table(juliabugs_source_gen_mooncake_results; backend=Val(:markdown))
println("### JuliaBUGS source gen (Enzyme) results:")
Benchmark._print_results_table(juliabugs_source_gen_enzyme_results; backend=Val(:markdown))
