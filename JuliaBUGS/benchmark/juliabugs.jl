const juliabugs_ad_examples = (
    :rats,
    :pumps,
    :dogs,
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
    :orange_trees,
    :orange_trees_multivariate,
    :air,
    :jaws,
    :birats,
    :schools,
    :beetles,
    :alligators,
    :endo,
)

const juliabugs_all_example = (
    :rats,
    :pumps,
    :dogs,
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
    :orange_trees,
    :orange_trees_multivariate,
    :biopsies,
    :eyes,
    :hearts,
    :air,
    :cervix,
    :jaws,
    :birats,
    :schools,
    :beetles,
    :alligators,
    :endo,
)

function _create_JuliaBUGS_model(model_name::Symbol)
    (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, model_name)
    return compile(model_def, data, inits)
end

# ! writing a _function_ to benchmark all models won't work because of world-age error

function benchmark_JuliaBUGS_model_with_Mooncake(model::JuliaBUGS.BUGSModel)
    # Use generated log density function for Mooncake
    model = JuliaBUGS.set_evaluation_mode(model, JuliaBUGS.UseGeneratedLogDensityFunction())
    ad_model = JuliaBUGS.BUGSModelWithGradient(model, AutoMooncake(; config=nothing))
    dim = LogDensityProblems.dimension(model)
    params_values = JuliaBUGS.getparams(model)
    density_time = Chairmarks.@be LogDensityProblems.logdensity($ad_model, $params_values)
    density_and_gradient_time = Chairmarks.@be LogDensityProblems.logdensity_and_gradient(
        $ad_model, $params_values
    )
    return BenchmarkResult(:juliabugs, dim, density_time, density_and_gradient_time)
end

# function benchmark_JuliaBUGS_model_with_Enzyme(model::JuliaBUGS.BUGSModel)
#     f(params, model) = LogDensityProblems.logdensity(model, params)
#     backend = AutoEnzyme()
#     dim = LogDensityProblems.dimension(model)
#     params_values = JuliaBUGS.getparams(model)
#     prep = prepare_gradient(f, backend, params_values, Constant(model))
#     density_time = Chairmarks.@be LogDensityProblems.logdensity($model, $params_values)
#     density_and_gradient_time = Chairmarks.@be gradient(
#         $f, $prep, $backend, $params_values, $(Constant(model))
#     )
#     return BenchmarkResult(:juliabugs_enzyme, dim, density_time, density_and_gradient_time)
# end
