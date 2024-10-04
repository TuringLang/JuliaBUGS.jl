using RCall
R"""
library(nimble)
nimbleOptions(enableDerivs = TRUE)
nimbleOptions(buildModelDerivs = TRUE)
nimbleOptions(allowDynamicIndexing = FALSE)

library(microbenchmark)
"""

# function to get log likelihood and gradient
# directly yanked from https://r-nimble.org/html_manual/example-maximum-likelihood-estimation-using-optim-with-gradients-from-nimderivs..html
R"""
logLikelihood_nf <- nimbleFunction(
  setup = function(model, paramNodes) {
    # Determine nodes for calculating the log likelihood for parameters given by
    # paramNodes, ignoring any priors.
    calcNodes <- model$getDependencies(paramNodes, self = FALSE)
    # Set up the additional arguments for nimDerivs involving model$calculate
    derivsInfo <- makeModelDerivsInfo(model, paramNodes, calcNodes)
    updateNodes <- derivsInfo$updateNodes
    constantNodes <- derivsInfo$constantNodes
    # Create a parameter transformation between original and unconstrained
    # parameter spaces.
    transformer <- parameterTransform(model, paramNodes)
  },
  methods = list(
    neg_logLikelihood_p = function(p = double(1)) {
      # Put values in model and calculate negative log likelihood.
      values(model, paramNodes) <<- p
      return(-model$calculate(calcNodes))
      returnType(double())
    },
    neg_logLikelihood = function(ptrans = double(1)) {
      # Objective function for optim,
      # using transformed parameter space.
      p <- transformer$inverseTransform(ptrans)
      return(neg_logLikelihood_p(p))
      returnType(double())
    },
    gr_neg_logLikelihood = function(ptrans = double(1)) {
      # Gradient of neg log likelihood
      p <- transformer$inverseTransform(ptrans)
      d <- derivs(neg_logLikelihood_p(p), wrt = 1:length(p), order = 1,
                  model = model, updateNodes = updateNodes,
                  constantNodes = constantNodes)
      return(d$jacobian[1,])
      returnType(double(1))
    },
    transform = function(p = double(1)) {
      # Give user access to the transformation ...
      return(transformer$transform(p))
      returnType(double(1))
    },
    inverse = function(ptrans = double(1)) { # ... and its inverse.
      return(transformer$inverseTransform(ptrans))
      returnType(double(1))
    }
  ),
  buildDerivs = 'neg_logLikelihood_p'
)
"""

# map the name used in JuliaBUGS.BUGSExamples to the name used in nimble
MODEL_VOL1_NIMBLE = (
    rats=:rats,
    pumps=:pump,
    seeds=:seeds,
    salm=:salm,
    equiv=:equiv,
    dyes=:dyes,
    epil=:epil,
    blockers=:blocker,
    oxford=:oxford, # give nans
    lsat=:lsat,
    # bones = :bones, # discrete parameters
    # mice = :mice, # not working, discrete parameters
    # kidney = :kidney, # same reason as mice
    # leuk = :leuk, # doesn't work
    # leukfr = :leukfr, # doesn't work
)

function create_nimble_model(model_name)
    nimble_model_name = MODEL_VOL1_NIMBLE[model_name]

    # r-Nimble installation comes with classic-bugs models, but we use the ones in benchmark/nimble/classic-bugs
    example_dir = joinpath(@__DIR__, "classic-bugs/vol1/$(nimble_model_name)")
    str = """
    model <- readBUGSmodel('$(nimble_model_name).bug', dir = '$(example_dir)')
    Cmodel <- compileNimble(model)
    """
    return reval(str)
end

function run_benchmark()
    # get parameters and dimension
    R"""
    stoch_nodes = model$getNodeNames(stochOnly = TRUE)
    parameters = stoch_nodes[!sapply(stoch_nodes, function(node) model$isData(node))]
    num_params <- length(parameters)
    rand_params <- runif(num_params)
    """

    # compile the model
    R"""
    ll_model <- logLikelihood_nf(model, parameters)
    cll_model <- compileNimble(ll_model, project = model)
    """

    # compute the log likelihood and its gradient once to ensure the computation is compiled
    R"""
    ll <- cll_model$neg_logLikelihood(rand_params)
    gr <- cll_model$gr_neg_logLikelihood(rand_params)
    """
    @rget ll
    @rget gr
    @show ll, gr

    # benchmark the log likelihood
    R"""
    nll_benchmark_result <- microbenchmark(
        cll_model$neg_logLikelihood(rand_params)
    )
    """

    # benchmark the gradient
    R"""
    gr_benchmark_result <- microbenchmark(
        cll_model$gr_neg_logLikelihood(rand_params)
    )
    """

    @rget nll_benchmark_result
    nll_median_time = Statistics.median(nll_benchmark_result.time) * 1e-6 # give in microseconds, convert to seconds
    @rget gr_benchmark_result
    gr_median_time = Statistics.median(gr_benchmark_result.time) * 1e-6

    return (nll_median_time, gr_median_time)
end

# note (some Nimble-provided models doesn't work out of the box, need to modify them)
# 1. add epil.bugs using content of epil2.bug
# 2. add `p.item[R,T]` to lsat var section

nimble_result = OrderedDict()
for model_name in keys(MODEL_VOL1_NIMBLE)
    println("Model: $model_name")
    create_nimble_model(model_name)
    nimble_result[model_name] = run_benchmark()
end

nimble_median_time_result = OrderedDict(
    model_name => gr_median_time_in_um * 1e-6 for
    (model_name, (nll_median_time, gr_median_time_in_um)) in nimble_result
)

nimble_median_time_result_micro = OrderedDict(
    model => get(nimble_median_time_result, model, 0.0) * 1e6 for
    model in keys(juliabugs_median_time_result)
)

## Not in use anymore

# some models can't be directly supported by nimble, because they require size information
using JuliaBUGS
function create_nimble_model_from_JuliaBUGSExamples(model_name)
    bugs_program = JuliaBUGS.BUGSExamples.VOLUME_1[model_name].original_syntax_program
    bugs_data = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].data))
    bugs_inits = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].inits))

    @rput bugs_program
    @rput bugs_data
    @rput bugs_inits

    open("bugs_program.bugs", "w") do file
        write(file, bugs_program)
    end

    R"""
    model <- readBUGSmodel(model = "bugs_program.bugs", data = bugs_data, inits = bugs_inits, buildDerivs = TRUE)
    Cmodel <- compileNimble(model)
    """

    return rm("bugs_program.bugs")
end

# The code below is taken from https://r-nimble.org/html_manual/cha-AD.html#derivatives-involving-model-calculations
# However, the performance is poor and the execution time is similar across all examples, indicating an issue.
# Therefore, we switch to using the approach from https://r-nimble.org/html_manual/example-maximum-likelihood-estimation-using-optim-with-gradients-from-nimderivs..html
# which is implemented in the function above.
# But this function may still be useful because `calculate` uses the values stored in the model without flattening them, so we can use this to compare the results
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
    return @rget derivs_result
    return @be reval("cDerives_all\$run(order = 1)")
end
