using Serialization
using DataFrames
using MetaGraphsNext

open("benchmark_results.bin", "w") do io
    serialize(
        io,
        Dict(
            "juliabugs_result" => juliabugs_result,
            "stan_result" => stan_result,
            "nimble_result" => nimble_result,
        ),
    )
end

function extract_median_time(result)
    return OrderedDict(
        model_name => Chairmarks.median(benchmark_result).time for
        (model_name, benchmark_result) in result
    )
end

result = open("benchmark_results.bin", "r") do io
    deserialize(io)
end

juliabugs_result = result["juliabugs_result"]
stan_result = result["stan_result"]
nimble_result = result["nimble_result"]

stan_median_time_result = extract_median_time(stan_result)
juliabugs_median_time_result = extract_median_time(juliabugs_result)
nimble_median_time_result = OrderedDict(
    model_name => gr_median_time_in_um * 1e-6 for
    (model_name, (nll_median_time, gr_median_time_in_um)) in nimble_result
)

juliabugs_median_time_result_micro = OrderedDict(
    model => time * 1e6 for (model, time) in juliabugs_median_time_result
)
stan_median_time_result_micro = OrderedDict(
    model => get(stan_median_time_result, model, 0.0) * 1e6 for
    model in keys(juliabugs_median_time_result)
)
nimble_median_time_result_micro = OrderedDict(
    model => get(nimble_median_time_result, model, 0.0) * 1e6 for
    model in keys(juliabugs_median_time_result)
)

model_parameters_count = OrderedDict()
model_data_count = OrderedDict()
for model_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
    (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name]
    model = compile(model_def, data, inits)
    model_parameters_count[model_name] = length(model.parameters)
    data_count = 0
    for l in labels(model.g)
        if model.g[l].is_observed
            data_count += 1
        end
    end
    model_data_count[model_name] = data_count
end

results_df = DataFrame(;
    Model=String[],
    Parameters=Int[],
    Data=Int[],
    Stan_Time=Union{Float64,Missing}[],
    JuliaBUGS_Time=Union{Float64,Missing}[],
    Nimble_Time=Union{Float64,Missing}[],
)

for model in keys(juliabugs_median_time_result_micro)
    stan_time = get(stan_median_time_result_micro, model, missing)
    juliabugs_time = juliabugs_median_time_result_micro[model]
    nimble_time = get(nimble_median_time_result_micro, model, missing)
    push!(
        results_df,
        (
            string(model),
            model_parameters_count[model],
            model_data_count[model],
            stan_time,
            juliabugs_time,
            nimble_time,
        ),
    )
end

using PrettyTables

pretty_table(results_df; backend=Val(:latex))
