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

function benchmark_generated_functions()
    model_def = @bugs begin
        μ ~ dnorm(0, 0.01)
        τ ~ dgamma(2, 2)
        for i in 1:N
            y[i] ~ dnorm(μ, τ)
        end
    end
    data = (N=10, y=collect(range(-1.0, 1.0; length=10)))
    graph = compile(model_def, data, (μ=0.0, τ=1.0))
    generated = JuliaBUGS.set_evaluation_mode(
        graph, JuliaBUGS.UseGeneratedLogDensityFunction()
    )
    for (adtype, model) in (
        (AutoForwardDiff(), graph),
        (AutoReverseDiff(), graph),
        (AutoMooncake(; config=nothing), graph),
        (AutoMooncake(; config=nothing), generated),
        (AutoMooncakeForward(; config=nothing), generated),
    )
        gradient_model = JuliaBUGS.BUGSModelWithGradient(model, adtype)
        x = JuliaBUGS.getparams(gradient_model.base_model)
        result = minimum(
            Chairmarks.@be LogDensityProblems.logdensity_and_gradient($gradient_model, $x)
        )
        println((; backend=adtype, mode=model.evaluation_mode, result.time, result.bytes))
    end
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
