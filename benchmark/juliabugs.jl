using JuliaBUGS
using ADTypes
using LogDensityProblems, LogDensityProblemsAD
using ReverseDiff
# using Tapir # cause some errors
# using Enzyme

using Chairmarks
using OrderedCollections

juliabugs_result = OrderedDict()
for model_name in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
    (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name]
    model = compile(model_def, data, inits)
    ad_model = ADgradient(AutoReverseDiff(true), model)
    # ad_model = ADgradient(AutoTapir(false), model)

    juliabugs_theta = rand(LogDensityProblems.dimension(model))
    juliabugs_result[model_name] = Chairmarks.@be LogDensityProblems.logdensity_and_gradient(
        $ad_model, $juliabugs_theta
    )
end
