using RCall
R"""
library(nimble)
nimbleOptions(enableDerivs = TRUE)
nimbleOptions(buildModelDerivs = TRUE)
nimbleOptions(allowDynamicIndexing = FALSE)
"""
R"library(microbenchmark)"

using JuliaBUGS
using ADTypes
using LogDensityProblems, LogDensityProblemsAD
using ReverseDiff
# using Tapir, Enzyme

using BridgeStan
using StanLogDensityProblems

using Chairmarks
using OrderedCollections

function create_bugs_stan_logdensityproblem(
    model_name,
    stan_bugs_examples_folder=joinpath(
        dirname(@__FILE__), "stan-example-models/bugs_examples/"
    ),
)
    stan_code_path = joinpath(
        stan_bugs_examples_folder, "vol1", String(model_name), "$(model_name).stan"
    )
    stan_data_path = joinpath(
        stan_bugs_examples_folder, "vol1", String(model_name), "$(model_name).data.json"
    )

    smb = BridgeStan.StanModel(stan_code_path, stan_data_path)
    sldp = StanLogDensityProblems.StanProblem(smb)
    return sldp
end

function create_nimble_model(model_name)
    bugs_program = JuliaBUGS.BUGSExamples.VOLUME_1[model_name].original_syntax_program
    bugs_data = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].data))
    bugs_inits = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].inits))

    @rput bugs_program
    @rput bugs_data
    @rput bugs_inits

    open("bugs_program.txt", "w") do file
        write(file, bugs_program)
    end
    R"""
    model <- readBUGSmodel(model = "bugs_program.txt", data = bugs_data, inits = bugs_inits, buildDerivs = TRUE)
    """
end

function run_nimble_benchmark(model_name)
    create_nimble_model(model_name)
    # reval("model_name <- '$(string(model_name))'")
    R"""
        # model <- readBUGSmodel(model_name, dir = getBUGSexampleDir(model_name), buildDerivs = TRUE)
        compiledModel <- compileNimble(model)

        # compiled log joint computation function
        # calculate_nf <- nimbleFunction(
        #     setup = function(model) {},
        #     run = function() {
        #         ans <- model$calculate()
        #         return(ans)
        #         returnType(double(0))
        #     }
        # )
        # calculate_result <- calculate_nf(model)
        # compiledCalculate <- compileNimble(calculate_result, project = model)
        # logp <- compiledCalculate$run()

        derivs_nf <- nimbleFunction(
        setup = function(model, with_respect_to_nodes, calc_nodes) {},
        run = function(order = integer(1),
                        reset = logical(0, default = FALSE)) {
            ans <- nimDerivs(model$calculate(calc_nodes), wrt = with_respect_to_nodes,
                            order = order, reset = reset)
            return(ans)
            returnType(ADNimbleList())
        }
        )
        wrt_nodes <- model$getNodeNames(stochOnly = TRUE)
        # Filter out data nodes
        wrt_nodes <- wrt_nodes[!sapply(wrt_nodes, function(node) model$isData(node))]
        calc_nodes <- model$getDependencies(wrt_nodes)
        derivs_all <- derivs_nf(model, wrt_nodes, calc_nodes)
        cDerives_all <- compileNimble(derivs_all, project = model)
        derivs_result <- cDerives_all$run(order = 1)
        # benchmark_result_median <- median(microbenchmark(cDerives_all$run(order = 1), times = 100)$time)
    """
    return @be reval("cDerives_all\$run(order = 1)")
end

models_vol1 = (
    # (:rats, :rats, :rats),
    # (:pumps, :pump, :pump),
    # (:seeds, :seeds, :seeds),
    # (:surgical_realistic, :surgical, nothing),
    # (:magnesium, :magnesium, nothing),
    # # # (:salm, :salm, :salm), # nimble errors
    # (:salm, :salm, nothing),
    (:equiv, :equiv, nothing),
    (:dyes, :dyes, :dyes),
    # (:stacks, :stacks, nothing), # stan has several version of this model
    # (:epil, :epil, :epil), # nimble names are different
    (:epil, :epil, nothing), # non-differentiable parameter
    (:blockers, :blocker, :blocker),
    (:oxford, :oxford, :oxford),
    # (:lsat, :lsat, :lsat), # nimble errors
    (:lsat, :lsat, nothing),
    (:bones, :bones, :bones),
    # (:mice, :mice, :mice), # nimble errors when compile ad function
    (:mice, :mice, nothing),
    # (:kidney, :kidney, :kidney),
    (:kidney, :kidney, nothing), # same issue as mice
    # (:leuk, :leuk, :leuk), # nimble errors
    (:leuk, :leuk, nothing),
)

result = OrderedDict()
for (juliabugs_name, stan_name, nimble_name) in models_vol1
    println("Running $juliabugs_name")
    # Set up JuliaBUGS model
    (; model_def, data, inits) = JuliaBUGS.BUGSExamples.VOLUME_1[juliabugs_name]
    juliabugs_logdensityproblem = nothing
    juliabugs_logdensityproblem = compile(model_def, data, inits)
    juliabugs_adgradient_reversediff = ADgradient(
        AutoReverseDiff(true), juliabugs_logdensityproblem
    )
    stan_logdensityproblem = create_bugs_stan_logdensityproblem(stan_name) # already does gradient

    stan_dim = LogDensityProblems.dimension(stan_logdensityproblem)
    stan_theta = rand(stan_dim)
    jbugs_dim = LogDensityProblems.dimension(juliabugs_logdensityproblem)
    jbugs_theta = rand(jbugs_dim)

    stan_result = @be LogDensityProblems.logdensity_and_gradient(
        $stan_logdensityproblem, $stan_theta
    )
    jbugs_result = @be LogDensityProblems.logdensity_and_gradient(
        $juliabugs_adgradient_reversediff, $jbugs_theta
    )
    if !isnothing(nimble_name)
        nimble_result = run_nimble_benchmark(juliabugs_name)
    else
        nimble_result = nothing
    end
    result[juliabugs_name] = (
        stan=stan_result, juliabugs=jbugs_result, nimble=nimble_result
    )
end

##

for names in keys(result)
    println("Model: $names")
    println("Stan:")
    Base.show(stdout, "text/plain", result[names].stan)
    println("\nJuliaBUGS:")
    Base.show(stdout, "text/plain", result[names].juliabugs)
    if !isnothing(result[names].nimble)
        println("\nNimble:")
        Base.show(stdout, "text/plain", result[names].nimble)
    end
    println("\n")
end
