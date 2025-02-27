using JuliaBUGS: _generate_lowered_model_def, _gen_log_density_computation_function_expr
using DifferentiationInterface: gradient, Constant

function benchmark_JuliaBUGS_source_gen(
    model::JuliaBUGS.BUGSModel, log_density_eval_function::Function; backend_str::Symbol
)
    if backend_str == :Mooncake
        logp = Base.Fix1(log_density_eval_function, model.evaluation_env)
        backend = AutoMooncake(; config=nothing)
        p = rand(LogDensityProblems.dimension(model))
        prep = prepare_gradient(logp, backend, p)
        density_time = Chairmarks.@be $logp($p)
        gradient_time = Chairmarks.@be gradient($logp, $prep, $backend, $p)
        return BenchmarkResult(
            :juliabugs_source_gen,
            LogDensityProblems.dimension(model),
            density_time,
            gradient_time,
        )
    elseif backend_str == :Enzyme
        backend = AutoEnzyme()
        p = rand(LogDensityProblems.dimension(model))
        f(p, env) = log_density_eval_function(env, p)
        prep = prepare_gradient(f, backend, p, Constant(model.evaluation_env))
        density_time = Chairmarks.@be log_density_eval_function($(model.evaluation_env), $p)
        gradient_time = Chairmarks.@be gradient(
            f, $prep, $backend, $p, $(Constant(model.evaluation_env))
        )
        return BenchmarkResult(
            :juliabugs_source_gen,
            LogDensityProblems.dimension(model),
            density_time,
            gradient_time,
        )
    else
        throw(ArgumentError("Invalid backend: $backend"))
    end
end
