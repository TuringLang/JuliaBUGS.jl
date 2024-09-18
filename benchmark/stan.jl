using BridgeStan
using StanLogDensityProblems

using JuliaBUGS
using ADTypes,LogDensityProblems, LogDensityProblemsAD
using ReverseDiff, Tapir, Enzyme

using Chairmarks

folder_filepath_bugs_examples = joinpath(dirname(@__FILE__), "stan-example-models/bugs_examples/")

differentiable_models_vol1 = Dict{Symbol,Symbol}(
    :rats => :rats, 
    :pumps => :pumps, 
    :seeds => :seeds, 
    :surgical => :surgical_realistic, 
    :magnesium => :magnesium,
    :salm => :salm, 
    :equiv => :equiv, 
    :stacks => :stacks, 
    :blocker => :blocker, 
    :oxford => :oxford,
)

# Set up Stan model
model_name = :rats
stan_code_path = joinpath(folder_filepath_bugs_examples, "vol1", String(model_name), "$(model_name).stan")
stan_data_path = joinpath(folder_filepath_bugs_examples, "vol1", String(model_name), "$(model_name).data.json")

smb = BridgeStan.StanModel(stan_code_path, stan_data_path)
sldp = StanLogDensityProblems.StanProblem(smb)

# Set up JuliaBUGS model
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name]
jbm = compile(model_def, data)

# Benchmark logdensity calculations
@be LogDensityProblems.logdensity(sldp, rand(LogDensityProblems.dimension(sldp)))
@be LogDensityProblems.logdensity(jbm, rand(LogDensityProblems.dimension(jbm)))

# Set up and benchmark gradient calculations
# ad_jbm_tapir = ADgradient(AutoTapir(false), jbm)
ad_jbm_reverse = ADgradient(AutoReverseDiff(true), jbm)
# ad_jbm_enzyme = ADgradient(AutoEnzyme(), jbm)
stan_dim = LogDensityProblems.dimension(sldp)
jbugs_dim = LogDensityProblems.dimension(jbm)
@be LogDensityProblems.logdensity_and_gradient($sldp, rand($stan_dim))
# @be LogDensityProblems.logdensity_and_gradient($ad_jbm_tapir, rand($jbugs_dim))
@be LogDensityProblems.logdensity_and_gradient($ad_jbm_reverse, rand($jbugs_dim))
# @be LogDensityProblems.logdensity_and_gradient($ad_jbm_enzyme, rand($jbugs_dim))
