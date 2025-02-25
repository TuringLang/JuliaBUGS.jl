const juliabugs_examples = (
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

const ad_error_examples = (:biopsies, :eyes, :hearts, :cervix)

function _create_JuliaBUGS_model(model_name::Symbol)
    (; model_def, data, inits) = getfield(JuliaBUGS.BUGSExamples, model_name)
    return compile(model_def, data, inits)
end

function benchmark_JuliaBUGS_model(model::JuliaBUGS.BUGSModel)
    ad_model = ADgradient(AutoReverseDiff(true), model)
    dim = LogDensityProblems.dimension(model)
    params_values = JuliaBUGS.getparams(model)
    density_time = Chairmarks.@be LogDensityProblems.logdensity($ad_model, $params_values)
    density_and_gradient_time = Chairmarks.@be LogDensityProblems.logdensity_and_gradient(
        $ad_model, $params_values
    )
    return BenchmarkResult(:juliabugs, dim, density_time, density_and_gradient_time)
end

# writing a _function_ to benchmark all models won't work because of world age issues
