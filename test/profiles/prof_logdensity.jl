using JuliaBUGS
using LogDensityProblems, LogDensityProblemsAD
using AdvancedHMC, AbstractMCMC, MCMCChains, ReverseDiff
using BenchmarkTools

suite = BenchmarkGroup()

for m in keys(JuliaBUGS.BUGSExamples.VOLUME_1)
    exempl = JuliaBUGS.BUGSExamples.VOLUME_1[m]
    (; model_def, data, inits) = exempl
    model = compile(model_def, data, inits)
    ad_model = ADgradient(:ReverseDiff, model; compile=Val(false))
    ad_model_compiled = ADgradient(:ReverseDiff, model; compile=Val(true))
    θ = rand(LogDensityProblems.dimension(model))

    sub_suite = BenchmarkGroup()

    sub_suite["non-AD model logdensity"] = @benchmarkable LogDensityProblems.logdensity(
        $model, $θ
    )
    sub_suite["AD model logdensity"] = @benchmarkable LogDensityProblems.logdensity(
        $ad_model, $θ
    )
    sub_suite["AD model logdensity with gradient"] = @benchmarkable LogDensityProblems.logdensity_and_gradient(
        $ad_model, $θ
    )
    sub_suite["AD model compiled logdensity"] = @benchmarkable LogDensityProblems.logdensity(
        $ad_model_compiled, $θ
    )
    sub_suite["AD model compiled logdensity with gradient"] = @benchmarkable LogDensityProblems.logdensity_and_gradient(
        $ad_model_compiled, $θ
    )

    suite[m] = sub_suite
end

tune!(suite)
results = run(suite; verbose=false)
result_dict = create_result_dict(results)
print_pure_text_table(result_dict)
