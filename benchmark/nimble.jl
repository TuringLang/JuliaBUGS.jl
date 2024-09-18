using RCall
using JuliaBUGS
using Chairmarks

models_vol1 = [:rats, :pumps, :seeds, :salm, :equiv, :dyes, :epil, :blocker, :oxford, :lsat, :bones, :mice, :kidney, :leuk]

# Load Nimble library in R
R"library(nimble)"

# Set up model
model_name = :pumps
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[model_name]

# Define function to set up Nimble model
function setup_nimble_model(model_name)
    model_string = """
    RModel <- readBUGSmodel('$model_name', dir = getBUGSexampleDir('$model_name'))
    compiledModel <- compileNimble(classicModel)
    """
    reval(model_string)
    return nothing
end

# Set up Nimble model
setup_nimble_model("pump")

# Compile JuliaBUGS model
jbugs_model = compile(model_def, data, inits)

# Benchmark calculations
@be reval("classicModel\$calculate()")
@be reval("compiledModel\$calculate()")
@be LogDensityProblems.logdensity(jbugs_model, rand(LogDensityProblems.dimension(jbugs_model)))
