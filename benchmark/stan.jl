using BridgeStan
using StanLogDensityProblems
using LogDensityProblems
using Chairmarks
using OrderedCollections

const STAN_BUGS_EXAMPLES_FOLDER = joinpath(
    dirname(@__FILE__), "stan-example-models/bugs_examples/"
)

const MODEL_VOL1_STAN = OrderedDict(
    :rats => (:rats, :rats),
    :pumps => (:pump, :pump),
    # :dogs => (:dogs, :dogs),
    :seeds => (:seeds, :seeds),
    :surgical_realistic => (:surgical, :surgical),
    :magnesium => (:magnesium, :magnesium),
    :salm => (:salm, :salm),
    :equiv => (:equiv, :equiv),
    :dyes => (:dyes, :dyes),
    :stacks => (:stacks, :stacks_d_normal_ridge),
    :epil => (:epil, :epil),
    :blockers => (:blocker, :blocker),
    :oxford => (:oxford, :oxford),
    :lsat => (:lsat, :lsat),
    :bones => (:bones, :bones),
    :mice => (:mice, :mice),
    :kidney => (:kidney, :kidney),
    :leuk => (:leuk, :leuk),
    :leukfr => (:leukfr, :leukfr),
)

function create_stan_logdensityproblem(volume, folder_name, file_name_prefix)
    stan_code_path = joinpath(
        STAN_BUGS_EXAMPLES_FOLDER,
        "vol$volume",
        String(folder_name),
        "$(file_name_prefix).stan",
    )
    stan_data_path = joinpath(
        STAN_BUGS_EXAMPLES_FOLDER,
        "vol$volume",
        String(folder_name),
        "$(file_name_prefix).data.json",
    )
    stan_model = BridgeStan.StanModel(stan_code_path, stan_data_path)
    return StanLogDensityProblems.StanProblem(stan_model)
end

function benchmark_stan_model(stan_logdensityproblem)
    stan_dim = LogDensityProblems.dimension(stan_logdensityproblem)
    stan_theta = rand(stan_dim)
    return Chairmarks.@be LogDensityProblems.logdensity_and_gradient(
        $stan_logdensityproblem, stan_theta
    )
end

function run_stan_benchmark(volume, model_name, model_path_dict)
    folder_name, file_name_prefix = model_path_dict[model_name]
    stan_logdensityproblem = create_stan_logdensityproblem(
        volume, folder_name, file_name_prefix
    )
    return benchmark_stan_model(stan_logdensityproblem)
end

function run_all_stan_benchmarks(volume, model_path_dict)
    return OrderedDict(
        model_name => run_stan_benchmark(volume, model_name, model_path_dict) for
        model_name in keys(model_path_dict)
    )
end

##

stan_result = run_all_stan_benchmarks(1, MODEL_VOL1_STAN)
