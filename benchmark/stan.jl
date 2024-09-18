using BridgeStan
using StanLogDensityProblems

using JuliaBUGS
using ADTypes
using LogDensityProblems, LogDensityProblemsAD
using ReverseDiff
# using Tapir, Enzyme

using Chairmarks

folder_filepath_bugs_examples = joinpath(
    dirname(@__FILE__), "stan-example-models/bugs_examples/"
)

models_vol1 = Dict{Symbol,Symbol}(
    :rats => :rats,
    :pumps => :pumps,
    :seeds => :seeds,
    :surgical => :surgical_realistic,
    :magnesium => :magnesium,
    :salm => :salm,
    :equiv => :equiv,
    :dyes => :dyes,
    :stacks => :stacks,
    :epil => :epil,
    :blocker => :blocker,
    :oxford => :oxford,
    :lsat => :lsat,
    :bones => :bones,
    :mice => :mice,
    :kidney => :kidney,
    :leuk => :leuk,
    :leukfr => :leukfr,
)

for (model_name, model_name_bugs) in pairs(models_vol1)
    # Set up Stan model
    stan_code_path = joinpath(
        folder_filepath_bugs_examples, "vol1", String(model_name), "$(model_name).stan"
    )
    stan_data_path = joinpath(
        folder_filepath_bugs_examples, "vol1", String(model_name), "$(model_name).data.json"
    )

    smb = BridgeStan.StanModel(stan_code_path, stan_data_path)
    sldp = StanLogDensityProblems.StanProblem(smb)

    # Set up JuliaBUGS model
    (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name_bugs]
    jbm = compile(model_def, data)

    # Benchmark logdensity calculations
    sldp_result = @be LogDensityProblems.logdensity(sldp, rand(LogDensityProblems.dimension(sldp)))
    jbm_result = @be LogDensityProblems.logdensity(jbm, rand(LogDensityProblems.dimension(jbm)))

    # Set up and benchmark gradient calculations
    # ad_jbm_tapir = ADgradient(AutoTapir(false), jbm)
    ad_jbm_reverse = ADgradient(AutoReverseDiff(true), jbm)
    # ad_jbm_enzyme = ADgradient(AutoEnzyme(), jbm)
    stan_dim = LogDensityProblems.dimension(sldp)
    jbugs_dim = LogDensityProblems.dimension(jbm)
    sldp_grad_result = @be LogDensityProblems.logdensity_and_gradient($sldp, rand($stan_dim))
    # @be LogDensityProblems.logdensity_and_gradient($ad_jbm_tapir, rand($jbugs_dim))
    jbm_grad_result = @be LogDensityProblems.logdensity_and_gradient($ad_jbm_reverse, rand($jbugs_dim))
    # @be LogDensityProblems.logdensity_and_gradient($ad_jbm_enzyme, rand($jbugs_dim))

    println("Model: $model_name")
    println()
    println("JuliaBUGS:")
    Base.show(stdout, MIME"text/plain"(), Chairmarks.median(jbm_result))
    println()
    println("Stan:")
    Base.show(stdout, MIME"text/plain"(), Chairmarks.median(sldp_result))
    println()
    println("JuliaBUGS gradient:")
    Base.show(stdout, MIME"text/plain"(), Chairmarks.median(jbm_grad_result))
    println()
    println("Stan gradient:")
    Base.show(stdout, MIME"text/plain"(), Chairmarks.median(sldp_grad_result))
    println()
end