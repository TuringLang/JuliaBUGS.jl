# the key is the name used by JuliaBUGS.BUGSExamples
# the value is a tuple of (volume, stan_model_folder_name, stan_model_file_name)
const stan_models_path_info = (
    rats=(1, :rats, :rats),
    pumps=(1, :pump, :pump),
    # dogs=(1, :dogs, :dogs),
    seeds=(1, :seeds, :seeds),
    surgical_realistic=(1, :surgical, :surgical),
    magnesium=(1, :magnesium, :magnesium),
    salm=(1, :salm, :salm),
    equiv=(1, :equiv, :equiv),
    dyes=(1, :dyes, :dyes),
    stacks=(1, :stacks, :stacks_d_normal_ridge),
    epil=(1, :epil, :epil),
    blockers=(1, :blocker, :blocker),
    oxford=(1, :oxford, :oxford),
    lsat=(1, :lsat, :lsat),
    bones=(1, :bones, :bones),
    mice=(1, :mice, :mice),
    kidney=(1, :kidney, :kidney),
    leuk=(1, :leuk, :leuk),
    leukfr=(1, :leukfr, :leukfr),
    dugongs=(2, :dugongs, :dugongs),
    air=(2, :air, :air),
    birats=(2, :birats, :birats),
    schools=(2, :schools, :schools),
    beetles=(2, :beetles, :beetles_logit),
    alligators=(2, :alli, :alli2),
)

const stan_examples_folder = joinpath(@__DIR__, "stan/bugs_examples/")

function _create_StanLogDensityProblem(model_name::Symbol)
    volume, stan_model_folder_name, stan_model_file_name = stan_models_path_info[model_name]
    stan_code_path = joinpath(
        stan_examples_folder,
        "vol$volume",
        String(stan_model_folder_name),
        "$(stan_model_file_name).stan",
    )
    stan_data_path = joinpath(
        stan_examples_folder,
        "vol$volume",
        String(stan_model_folder_name),
        "$(stan_model_file_name).data.json",
    )
    model = BridgeStan.StanModel(stan_code_path, stan_data_path)
    return StanLogDensityProblems.StanProblem(model)
end

function benchmark_Stan_model(model::StanLogDensityProblems.StanProblem)
    dim = LogDensityProblems.dimension(model)
    params_values = rand(dim)
    density_time = Chairmarks.@be LogDensityProblems.logdensity($model, $params_values)
    density_and_gradient_time = Chairmarks.@be LogDensityProblems.logdensity_and_gradient(
        $model, $params_values
    )
    return BenchmarkResult(:stan, Int(dim), density_time, density_and_gradient_time)
end

function benchmark_Stan_models(
    examples_to_benchmark::Vector{Symbol}=collect(keys(stan_models_path_info))
)
    results = OrderedDict{Symbol,BenchmarkResult}()
    for model_name in examples_to_benchmark
        @info "Benchmarking $model_name"
        model = _create_StanLogDensityProblem(model_name)
        results[model_name] = benchmark_Stan_model(model)
    end
    return results
end
